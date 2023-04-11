Shader "BasicLightingModel/Phong+HalfLambert"
{
    Properties
    {
        _Emissive("_Emissive",Color) = (1,1,1,1)
        _SpecularIntensity("SpecularIntensity",float) = 1
    }
    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" "RenderType"="Opaque" "Queue"="Geometry" }
        LOD 100

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Input.hlsl"
            
            struct appdata
            {
                float4 vertex : POSITION;
                float4 normal : NORMAL;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float3 worldPos : TEXCOORD1;
                float3 worldNormal : TEXCOORD2;
                float4 clipPos : SV_POSITION;
            };
            
            float _SpecularIntensity;
            half3 _Emissive;

            v2f vert (appdata v)
            {
                v2f o=(v2f)0;
                o.worldNormal = TransformObjectToWorldNormal(v.normal.xyz);
                o.worldPos = TransformObjectToWorld(v.vertex.xyz);
                o.clipPos = TransformObjectToHClip(v.vertex.xyz);
                return o;
            }

            half4 frag (v2f i) : SV_Target
            {
                //归一化世界法线
                float3 worldNormal = normalize(i.worldNormal);
                //归一化视线方向
                float3 worldViewDir = normalize(_WorldSpaceCameraPos);
                //获取MainLight
                Light mainLight = GetMainLight();
                //归一化光照方向
                float3 worldLightDir = normalize(mainLight.direction);
                //归一化反射方向
                float3 worldLightReflectDir=normalize(reflect(-worldLightDir,worldNormal));
                
                //直接光漫反射
                half3 diffuse = dot(worldNormal,worldLightDir)*0.5+0.5;
                //直接光镜面反射
                half3 specular = pow(max(0,dot(worldLightReflectDir,worldViewDir)),_SpecularIntensity);
                //环境光
                half3 ambient = half3(unity_SHAr.w, unity_SHAg.w, unity_SHAb.w);
                //自发光
                half3 emissive = _Emissive.rgb;

                return half4(diffuse * specular * ambient * emissive,1);
            }
            ENDHLSL
        }
    }
}
