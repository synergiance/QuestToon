// License: MIT
// Author: Synergiance

Shader "Synergiance/QuestToon" {
	Properties {
		_MainTex ("Albedo Texture", 2D) = "white" {}
		_Color ("Albedo Color", Color) = (1, 1, 1, 1)
		_Shadow ("Shadow Coverate", Range(0, 1)) = 0.5
		_ShadowBlur ("Shadow Blur", Range(0, 1)) = 0.01
		[NoScaleOffset] _EmissionMap ("Emission", 2D) = "black" {}
		[HDR] _Emission ("Emission", Color) = (0, 0, 0)
		_StaticToonLight ("Static Light", Vector) = (1,1.5,1.5,0)
		[Enum(Off,0,Front,1,Back,2)] _CullMode ("Cull Mode", Float) = 2.0
	}
	
	SubShader {
		
		Tags {
			"Queue" = "Geometry"
		}
		
		Cull [_CullMode]
		
		Pass {
			Tags {
				"LightMode" = "ForwardBase"
				"RenderMode" = "Opaque"
			}
			
			Blend One Zero
			ZWrite On
			
			CGPROGRAM
			
			#pragma vertex vert
			#pragma fragment frag
			
			#pragma multi_compile_fwdbase
			#pragma multi_compile_fog
			//#pragma multi_compile _ _EMISSION // Not implemented
			
			#define FORWARD_BASE_PASS
			
			#include "QuestToon.cginc"
			
			ENDCG
		}
		
		Pass {
			Tags {
				"LightMode" = "ForwardAdd"
			}
			
			Blend One One
			ZWrite Off
			
			CGPROGRAM
			
			#pragma vertex vert
			#pragma fragment frag
			
			#pragma multi_compile_fwdadd
			#pragma multi_compile_fog
			
			#include "QuestToon.cginc"
			
			ENDCG
		}
	}
}