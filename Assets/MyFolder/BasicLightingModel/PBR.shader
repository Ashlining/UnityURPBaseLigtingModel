Shader "BasicLightingModel/PBR"
{
    Properties
    {
        _Color ("Color", Color) = (1,1,1,1)
        _MainTex ("Albedo (RGB)", 2D) = "white" {}
        _Roughness ("Roughness", Range(0,1)) = 0.5
        //Gamma矫正金属度变化 ，这个矫正是否有必要？做截图对比
        [Gamma]_Metallic ("Metallic", Range(0,1)) = 0.0
    }
    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" "RenderType"="Opaque" }
        LOD 200
        Pass
		{
            HLSLPROGRAM

            #pragma target 3.0

            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Input.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/GlobalIllumination.hlsl"

            float4 _Color;
            float _Metallic;
            float _Roughness;
            sampler2D _MainTex;
            float4 _MainTex_ST;

            struct a2v
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float4 vertex : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 normal : TEXCOORD1;
                float3 worldPos : TEXCOORD2;
            };

            v2f vert(a2v v)
            {
                v2f o;
                o.vertex = TransformObjectToHClip(v.vertex.xyz);
                o.worldPos = TransformObjectToWorld(v.vertex.xyz);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                o.normal = TransformObjectToWorldNormal(v.normal);
                return o;
            }

            inline half Pow5 (half x)
            {
                return x*x * x*x * x;
            }

            //正态分布函数D
            float Distribution(float roughness , float nh)
            {
                float lerpSquareRoughness = pow(lerp(0.002, 1, roughness), 2);
                float D = lerpSquareRoughness / (pow((pow(nh, 2) * (lerpSquareRoughness - 1) + 1), 2) * PI);
                return D;
            }

            //几何遮蔽G
            float Geometry(float roughness , float nl , float nv)
            {
                float kInDirectLight = pow(roughness + 1, 2) / 8;
                float kInIBL = pow(roughness, 2) / 8;
                float GLeft = nl / lerp(nl, 1, kInDirectLight);
                float GRight = nv / lerp(nv, 1, kInDirectLight);
                float G = GLeft * GRight;
                return G;
            }

            //菲尼尔Fresnel
            float3 FresnelEquation(float3 F0 , float vh)
            {
                float3 F = F0 + (1 - F0) * exp2((-5.55473 * vh - 6.98316) * vh);
                return F;
            }

            //立方体贴图的Mip等级计算
            float CubeMapMip(float _Roughness)
            {
                //基于粗糙度计算CubeMap的Mip等级
                float mip_roughness = _Roughness * (1.7 - 0.7 * _Roughness);
                half mip = mip_roughness * UNITY_SPECCUBE_LOD_STEPS; 
                return mip;
            }

            //间接光的菲涅尔系数
            float3 fresnelSchlickRoughness(float cosTheta, float3 F0, float roughness)
            {
                return F0 + (max(float3(1 ,1, 1) * (1 - roughness), F0) - F0) * pow(1.0 - cosTheta, 5.0);
            }

            half4 frag(v2f i) : SV_Target
            {
                //**********准备数据************
                float3 normal = normalize(i.normal);
                Light light=GetMainLight();
                float3 lightDir = normalize(light.direction);
                float3 viewDir = normalize(_WorldSpaceCameraPos.xyz - i.worldPos.xyz);
                float3 lightColor = light.color;
                float3 halfVector = normalize(lightDir + viewDir);      //半角向量

                float roughness = _Roughness * _Roughness;
                float squareRoughness = roughness * roughness;

                float3 Albedo = _Color.rgb * tex2D(_MainTex, i.uv).xyz;     //颜色

                //对每个数据做限制，防止除0
                float nl = max(saturate(dot(i.normal, lightDir)), 0.000001);
                float nv = max(saturate(dot(i.normal, viewDir)), 0.000001);
                float vh = max(saturate(dot(viewDir, halfVector)), 0.000001);
                float lh = max(saturate(dot(lightDir, halfVector)), 0.000001);
                float nh = max(saturate(dot(i.normal, halfVector)), 0.000001);
                //**********分割************

                //********直接光照-镜面反射部分*********
                float D = Distribution(roughness , nh);
                float G = Geometry(roughness , nl , nv);
                float3 F0 = lerp(kDielectricSpec.rgb, Albedo, _Metallic);
                float3 F = FresnelEquation(F0 , vh);

                float3 SpecularResult = (D * G * F) / (nv * nl * 4);
                float3 specColor = SpecularResult * lightColor * nl * PI;
                specColor = saturate(specColor);
                //********直接光照-镜面反射部分完成*********    

                //********直接光照-漫反射部分*********
                float3 kd = (1 - F)*(1 - _Metallic);
                float3 diffColor = kd * Albedo * lightColor * nl;
                //********直接光照-漫反射部分完成*********

                float3 directLightResult = diffColor + specColor;   //直接光照部分结果
                //********直接光照部分完成*********

                //***********间接光照-镜面反射部分********* 
                half mip = CubeMapMip(_Roughness);                              //计算Mip等级，用于采样CubeMap
                float3 reflectVec = reflect(-viewDir, i.normal);                //计算反射向量，用于采样CubeMap
                
                half4 rgbm = unity_SpecCube0.SampleLevel(samplerunity_SpecCube0,reflectVec,mip);
                float3 iblSpecular = DecodeHDREnvironment(rgbm, unity_SpecCube0_HDR);      //采样CubeMap之后，储存在四维向量rgbm中，然后在使用函数DecodeHDR解码到rgb

                half surfaceReduction=1.0/(roughness*roughness+1.0);            //压暗非金属的反射

                float oneMinusReflectivity = kDielectricSpec .a-kDielectricSpec .a*_Metallic;
                half grazingTerm=saturate((1 - _Roughness)+(1-oneMinusReflectivity));
                half t = Pow5(1-nv);
                float3 FresnelLerp =  lerp(F0,grazingTerm,t);                   //控制反射的菲涅尔和金属色

                float3 iblSpecularResult = surfaceReduction*iblSpecular*FresnelLerp;
                //***********间接光照-镜面反射部分完成********* 

                //***********间接光照-漫反射部分********* 
                half3 iblDiffuse = SampleSH(normal);                  //获取球谐光照

                float3 Flast = fresnelSchlickRoughness(max(nv, 0.0), F0, roughness);
                float kdLast = (1 - Flast).x * (1 - _Metallic);                   //压暗边缘，边缘处应当有更多的镜面反射

                float3 iblDiffuseResult = iblDiffuse * kdLast * Albedo;
                //***********间接光照-漫反射部分完成********* 
                float3 indirectResult = iblSpecularResult + iblDiffuseResult;
                //***********间接光照完成********* 

                float3 finalResult = directLightResult + indirectResult;

                return half4(finalResult,1);
            }
            ENDHLSL
        }
    }
}