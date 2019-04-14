// License: MIT
// Author: Synergiance

#if !defined(SYNQUESTTOON_INCLUDE)
#define SYNQUESTTOON_INCLUDE

#include "UnityPBSLighting.cginc"
#include "AutoLight.cginc"

#if defined(FOG_LINEAR) || defined(FOG_EXP) || defined(FOG_EXP2)
	#if !defined(FOG_DISTANCE)
		#define FOG_DEPTH 1
	#endif
	#define FOG_ON 1
#endif

sampler2D _MainTex;
float4 _MainTex_ST;
half4 _Color;

sampler2D _EmissionMap;
half3 _Emission;

float _Shadow;
float _ShadowBlur;

half4 _StaticToonLight;

struct vertdata {
	float4 vertex : POSITION;
	float3 normal : NORMAL;
	float2 uv : TEXCOORD0;
};

struct v2f {
	float4 pos : SV_POSITION;
	float3 normal : NORMAL;
	float2 uv : TEXCOORD0;
	
	#if FOG_DEPTH
		float4 worldPos : TEXCOORD1;
	#else
		float3 worldPos : TEXCOORD1;
	#endif
	
	SHADOW_COORDS(2)
	
	#if defined(VERTEXLIGHT_ON)
		half3 vertexLightColor : TEXCOORD3;
	#endif
};

void ComputeVertexLightColor (inout v2f i) {
	#if defined(VERTEXLIGHT_ON)
		i.vertexLightColor = Shade4PointLights(
			unity_4LightPosX0, unity_4LightPosY0, unity_4LightPosZ0,
			unity_LightColor[0].rgb, unity_LightColor[1].rgb,
			unity_LightColor[2].rgb, unity_LightColor[3].rgb,
			unity_4LightAtten0, i.worldPos.xyz, i.normal
		);
	#endif
}

v2f vert(vertdata v) {
	
	v2f i;
	
	i.pos = UnityObjectToClipPos(v.vertex);
	i.worldPos.xyz = mul(unity_ObjectToWorld, v.vertex);
	i.normal = UnityObjectToWorldNormal(v.normal);
	
	#if FOG_DEPTH
		i.worldPos.w = i.pos.z;
	#endif
	
	i.uv.xy = TRANSFORM_TEX(v.uv, _MainTex);
	
	TRANSFER_SHADOW(i);
	
	ComputeVertexLightColor(i);
	return i;
}

half3 GetEmission(v2f i) {
	#if defined(FORWARD_BASE_PASS)
		// This keyword is defined in the standard shader but the code is disabled since I need to implement a UI still
		//#if defined(_EMISSION)
			return tex2D(_EmissionMap, i.uv.xy) * _Emission;
		//#else
		//	return _Emission;
		//#endif
	#else
		return 0;
	#endif
}

half3 GetAlbedo(v2f i) {
	half3 albedo = tex2D(_MainTex, i.uv.xy) * _Color;
	return albedo;
}

// Texture is sampled twice but unity will optimize this into a single texture sample.
fixed GetAlpha(v2f i) {
	fixed alpha = 1;
	#ifdef _ALPHABLEND_ON
		alpha = _Color.a * tex2D(_MainTex, i.uv.xy).a;
	#endif
	return alpha;
}

UnityLight CreateLight(v2f i) {
	UnityLight light;
	#if defined(POINT) || defined(POINT_COOKIE) || defined(SPOT)
		light.dir = normalize(_WorldSpaceLightPos0 - i.worldPos.xyz);
	#else
		light.dir = _WorldSpaceLightPos0.rgb;
		if (light.dir.x + light.dir.y + light.dir.z < 0.01) {
			light.dir.xyz = _StaticToonLight.xyz;
		}
	#endif
	
	light.color = _LightColor0.rgb;
	
	// This is the UNITY_LIGHT_ATTENUATION macro with the SHADOW_ATTENUATION macro removed
	#if defined(POINT)
		unityShadowCoord3 lightCoord = mul(unity_WorldToLight, unityShadowCoord4(i.worldPos.xyz, 1)).xyz;
		fixed attenuation = tex2D(_LightTexture0, dot(lightCoord, lightCoord).rr).UNITY_ATTEN_CHANNEL;
		light.color *= attenuation;
	#elif defined(POINT_COOKIE)
		unityShadowCoord3 lightCoord = mul(unity_WorldToLight, unityShadowCoord4(i.worldPos.xyz, 1)).xyz;
		fixed attenuation = tex2D(_LightTexture0, dot(lightCoord, lightCoord).rr).UNITY_ATTEN_CHANNEL * texCUBE(_LightTexture0, lightCoord).w;
		light.color *= attenuation;
	#elif defined(SPOT)
		unityShadowCoord4 lightCoord = mul(unity_WorldToLight, unityShadowCoord4(i.worldPos.xyz, 1));
		fixed attenuation = (lightCoord.z > 0) * UnitySpotCookie(lightCoord) * UnitySpotAttenuate(lightCoord.xyz);
		light.color *= attenuation;
	#elif defined(DIRECTIONAL_COOKIE)
		unityShadowCoord4 lightCoord = mul(unity_WorldToLight, unityShadowCoord4(i.worldPos.xyz, 1)).xy;
		fixed attenuation = tex2D(_LightTexture0, lightCoord).w;
		light.color *= attenuation;
	#endif
	
	// The following line is commented out because it doesn't work correctly and because shadows are expensive on quest
	//light.color *= SHADOW_ATTENUATION(input);
	
	return light;
}

UnityIndirect CreateIndirectLight(v2f i) {
	UnityIndirect indirectLight;
	indirectLight.diffuse = 0;
	indirectLight.specular = 0;
	
	#if defined(VERTEXLIGHT_ON)
		indirectLight.diffuse = i.vertexLightColor;
	#endif
	
	#if defined(FORWARD_BASE_PASS)
		indirectLight.diffuse += max(0, ShadeSH9(float4(i.normal, 1)));
	#endif
	
	return indirectLight;
}

half4 ApplyFog(half4 color, v2f i) {
	#if FOG_ON
		float viewDistance = length(_WorldSpaceCameraPos - i.worldPos.xyz);
		#if FOG_DEPTH
			viewDistance = UNITY_Z_0_FAR_FROM_CLIPSPACE(i.worldPos.w);
		#endif
		UNITY_CALC_FOG_FACTOR_RAW(viewDistance);
		half3 fogColor = 0;
		#if defined(FORWARD_BASE_PASS)
			fogColor = unity_FogColor.rgb;
		#endif
		color.rgb = lerp(fogColor, color.rgb, saturate(unityFogFactor));
	#endif
	return color;
}

// The logic here isn't perfect but it is cheap on GPU hardware, also does away with a texture lookup from toon ramps
half3 ToonShade(v2f i, half3 albedo, UnityLight light, UnityIndirect indirectLight) {
	half3 lightColor = (light.color * smoothstep(_Shadow - _ShadowBlur * 0.5, _Shadow + _ShadowBlur * 0.5, dot(light.dir, normalize(i.normal)) * 0.5 + 0.5)) + indirectLight.diffuse;
	return lightColor * albedo;
}

half4 frag(v2f i) : SV_TARGET {
	half3 albedo = GetAlbedo(i);
	
	half3 color = ToonShade(i, albedo, CreateLight(i), CreateIndirectLight(i));
	color.rgb += GetEmission(i);
	
	return ApplyFog(half4(color, GetAlpha(i)), i);
}

#endif
