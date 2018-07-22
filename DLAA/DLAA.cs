using UnityEngine;

[ExecuteInEditMode, RequireComponent(typeof(Camera))]
public class DLAA : MonoBehaviour
{
    public Shader shader;
    public bool preserveHighlights = true;

    Material m_Material;

    enum Pass : int
    {
        PreFilter,
        DLAA,
        DLAAPreserveHighlights
    }

    void OnDisable()
    {
        DestroyImmediate(m_Material);
        m_Material = null;
    }

    void OnRenderImage(Texture source, RenderTexture destination)
    {
        if (shader == null)
        {
            Debug.LogWarning("Shader for DLAA is missing");
            Graphics.Blit(source, destination);
            return;
        }

        if (m_Material == null)
            m_Material = new Material(shader) { hideFlags = HideFlags.HideAndDontSave };

        var highPassRT = RenderTexture.GetTemporary(source.width, source.height, 0, RenderTextureFormat.ARGB32);

        Graphics.Blit(source, highPassRT, m_Material, (int)Pass.PreFilter);
        Graphics.Blit(highPassRT, destination, m_Material, preserveHighlights ? (int)Pass.DLAAPreserveHighlights : (int)Pass.DLAA);

        RenderTexture.ReleaseTemporary(highPassRT);
    }
}
