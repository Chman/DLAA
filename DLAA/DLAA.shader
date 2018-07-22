Shader "Hidden/DLAA"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }

    CGINCLUDE
            
        #pragma target 4.5

    ENDCG

    SubShader
    {
        Cull Off ZWrite Off ZTest Always

        Pass
        {
            CGPROGRAM

                #pragma vertex Vert
                #pragma fragment FragPreFilter
                #include "DLAA.cginc"

            ENDCG
        }

        Pass
        {
            CGPROGRAM

                #pragma vertex Vert
                #pragma fragment FragDLAA
                #include "DLAA.cginc"

            ENDCG
        }

        Pass
        {
            CGPROGRAM

                #pragma vertex Vert
                #pragma fragment FragDLAA
                #define PRESERVE_HIGHLIGHTS
                #include "DLAA.cginc"

            ENDCG
        }
    }
} 