"""
lefture_backend/app/services/prompts/art_styles_catalog.py

Curated Visual Art Styles for leFture Review Cards.
The first 100 are 5 Primary Categories x 4 Sub-Categories x 5 Specific Styles, balanced with ~75% versatile,
timeless classic/modern styles and ~25% evocative accents; a 6th category of futuristic / mystical / ornamental
styles follows. Each style describes the medium, textures, and light only. It must not name a place or an
object (a "seaside poster" puts every topic at the seaside), because the style is shared by every topic image
of a lecture and the scenes have to stay free to follow each topic.
"""

import random
from typing import Dict, List

ART_STYLES_BY_CATEGORY: Dict[str, Dict[str, List[str]]] = {
    # =========================================================================
    # 1. PHOTOGRAPHY & CINEMATIC (20 Styles)
    # =========================================================================
    "photography_and_cinematic": {
        "35mm_and_analog_film": [
            "Cinematic 35mm film photograph with warm natural golden-hour backlight and gentle analog grain",
            "35mm street photography still, natural afternoon light, candid unposed moment, rich cinematic depth",
            "Cinematic editorial photograph, soft sunlight streaming through large open windows, peaceful living atmosphere",
            "Atmospheric 35mm film still, gentle evening dusk light, warm streetlamps, quiet thoughtful mood",
            "Warm nostalgic 35mm photograph, soft natural sun flare, authentic cozy interior, gentle earthy tones",
        ],
        "medium_format_and_editorial": [
            "Hasselblad medium-format editorial photograph, crisp natural daylight, creamy depth of field, elegant simplicity",
            "Modern architectural photograph, clean geometric lines, soft directional morning sunlight, serene tranquil space",
            "Editorial environmental portrait style, subject in their sunlit natural workspace, soft authentic textures",
            "High-end studio still-life photograph, soft diffused overhead lighting, gentle shadows, refined tactile materials",
            "Bright and airy Scandinavian lifestyle photograph, pale natural wood, soft organic shadows, serene clarity",
        ],
        "nature_and_landscapes": [
            "Documentary travel photograph in bold midday light, crisp saturated color, high-contrast clarity, sweeping wide-angle depth",
            "Atmospheric photograph in pale morning light, soft airy haze, gentle breeze-like movement, quiet openness",
            "Serene documentary photograph under soft overcast light, muted natural palette, gentle even tones, quiet openness",
            "Golden-hour wide-angle photograph, soft layered atmospheric depth, warm amber glow, expansive scale",
            "Soft misty-morning photograph, diffused pale light, gentle atmospheric haze with sunbeams breaking through, natural depth of field",
        ],
        "atmospheric_and_cinematic_light": [
            "Cinematic blue-hour photograph, warm interior lamplight glowing through wet glass windows after evening rain",
            "Dramatic chiaroscuro cinema still, rich natural contrast, single warm shaft of light illuminating the subject",
            "Quiet cinematic sunrise photograph, soft pastel pink and amber gradient sky over a waking city or countryside",
            "Cinematic low-light night photograph, deep indigo sky lit by soft natural starlight, rich atmospheric depth, fine photographic grain",
            "Sun-drenched afternoon interior photography, long golden shadows stretching across warm wooden floorboards",
        ],
    },

    # =========================================================================
    # 2. FINE ART & TRADITIONAL PAINTING (20 Styles)
    # =========================================================================
    "fine_art_and_traditional_painting": {
        "modern_and_classical_oil": [
            "Luminous oil painting on coarse canvas, expressive textured brushstrokes, warm natural light and rich depth",
            "Contemporary expressive oil on linen, loose energetic palette knife marks, vibrant harmonious colors",
            "Warm atmospheric oil painting, soft golden sunlight diffusing through gentle painterly haze",
            "Classical still-life oil painting, deep rich shadows, luminous focused highlights, elegant timeless beauty",
            "Modern impressionist oil painting, visible rhythmic brush marks, dancing dappled sunlight, joyful energy",
        ],
        "fresh_and_botanical_watercolor": [
            "Fresh layered watercolor on heavy cold-pressed cotton paper, translucent color washes, soft edges, airy light",
            "Delicate watercolor illustration, fine organic contours, vibrant natural pigment blends, clean white paper",
            "Luminous architectural watercolor sketch, loose pencil linework, breezy sunlit color washes, lively atmosphere",
            "Soft atmospheric watercolor, gentle pigment granulation, misty blended edges, generous negative space",
            "Contemporary watercolor and ink study, fluid organic shapes, delicate pen details, bright optimistic colors",
        ],
        "opaque_gouache_and_storybook": [
            "Charming editorial gouache illustration, velvety matte opaque colors, whimsical architectural charm, warm daylight",
            "Mid-century children's storybook art in matte gouache, playful simplified shapes, cheerful nostalgic warmth",
            "Warm folk-art gouache painting on toned paper, decorative patterned motifs, cozy handmade atmosphere, gentle light",
            "Modern gouache illustration, flat stylized geometric shapes, bold clean color blocking, sunny disposition",
            "Soft pastel and chalk artwork on textured paper, velvety blended colors, comforting peaceful mood",
        ],
        "classic_sketch_and_printmaking": [
            "Refined colored pencil and graphite illustration, soft cross-hatching, warm tactile paper texture, thoughtful precision",
            "Classic pen-and-ink illustration with delicate watercolor tint, fine cross-hatching, vintage storybook warmth",
            "Traditional Shin-Hanga woodblock print, soft atmospheric gradients, luminous glowing accents, washi paper texture",
            "Bold relief linocut print on fibrous paper, strong graphic black lines, warm two-tone ink overlays, artisanal feel",
            "Hand-pulled silkscreen print on textured rag paper, clean overlapping color fields, deliberate artisanal charm",
        ],
    },

    # =========================================================================
    # 3. STYLIZED 3D & DIGITAL WORLDS (20 Styles)
    # =========================================================================
    "stylized_3d_and_digital_worlds": {
        "warm_animation_and_character": [
            "Charming 3D animated feature film style, soft tactile materials, warm volumetric sunlight, heartwarming expressive appeal",
            "Whimsical 3D animated style, soft rounded shapes, warm lamplight glow, welcoming atmosphere",
            "Stylized 3D digital scene, soft matte pastel textures, gentle ambient bounce lighting, cheerful playful mood",
            "Cozy 3D animated still, warm sunlit glow, soft atmospheric haze, loving handcrafted detail",
            "Playful stylized 3D look, soft rounded forms, warm sunlight, expansive airy depth",
        ],
        "modern_isometric_and_architectural": [
            "Clean modern isometric 3D illustration, stylish architecture, tidy functional rooms, soft natural daylight",
            "Intricate isometric 3D illustration, layered cutaway viewpoint revealing inner detail, crisp geometry",
            "Stylized isometric 3D illustration at dusk, warm glowing lights, clean modern design",
            "Isometric 3D illustration with translucent glass accents, fresh green touches, bright dappled sunlight",
            "Low-poly faceted 3D illustration, crisp angular planes, soft gradient lighting, cheerful modern color",
        ],
        "clean_minimalist_and_clay_3d": [
            "Tactile claymation miniature world, soft matte clay models, gentle studio rim lighting, friendly handcrafted charm",
            "Clean minimalist 3D rendering, smooth geometric primitives, soft pastel tones, velvety matte finish",
            "Modern 3D product-design concept aesthetic, elegant matte materials, pristine studio lighting, crisp sophisticated shadows",
            "Hand-painted wooden toy aesthetic in 3D, smooth woodgrain textures, rounded friendly edges, Scandinavian design",
            "Ceramic figurine aesthetic in 3D, satin glaze, delicate pastel accents, soft studio reflections, charming simplicity",
        ],
        "atmospheric_and_volumetric_3d": [
            "Cinematic volumetric 3D scene, radiant god rays streaming through soft atmosphere, solemn and majestic",
            "Atmospheric 3D architectural render, morning light filtering through concrete and glass, calm minimalist poetry",
            "Luminous translucent 3D scene, frosted glass shapes refracting gentle ambient rainbow light, modern art installation",
            "Sunlit 3D scene, warm stone-toned materials, soft blooming color accents, peaceful atmospheric depth",
            "Lyrical twilight 3D render, tranquil reflective surfaces, softly glowing light orbs, calm serene evening ambiance",
        ],
    },

    # =========================================================================
    # 4. GRAPHIC DESIGN, PRINT & POSTERS (20 Styles)
    # =========================================================================
    "graphic_design_and_posters": {
        "modern_editorial_vector": [
            "Modern vector illustration, clever visual metaphor, sophisticated palette, confident clean shapes",
            "Contemporary flat-graphic artwork, clean stylized silhouettes, bold color-blocking, elegant storytelling",
            "High-end Scandinavian editorial graphic, serene organic curves, warm neutral earth tones, contemplative balance",
            "Dynamic modern vector poster, strong visual hierarchy, elegant negative space, cheerful uplifting atmosphere",
            "Modern line-art illustration with flat color accents, graceful continuous contours, airy open composition",
        ],
        "mid_century_and_vintage_poster": [
            "Vintage 1950s atomic-age illustration, simplified boomerang and starburst shapes, halftone shading, optimistic sunny colors",
            "Mid-century modern exhibition poster, clean geometric architecture, warm optimistic sunlight, stylish balance",
            "Streamlined Art Deco-era poster illustration, sleek curved shapes, vibrant sun-warmed palette, subtle lithographic grain",
            "Vintage screenprint poster aesthetic, rich layered color-blocking, bold simplified silhouettes, weathered paper grain, nostalgic warmth",
            "Mid-century travel-poster gouache illustration, bold flat color blocks, crisp geometric shapes, sparkling sun-drenched light, vintage lithographic grain",
        ],
        "risograph_and_screenprint": [
            "Modern Risograph art print, semi-transparent warm coral and teal ink overlaps, organic dot gain, tactile paper grain",
            "Bold two-tone Risograph illustration, energetic halftone dot patterns, dynamic composition, indie editorial charm",
            "Four-color screenprinted art poster on raw kraft paper, tactile ink layers, deliberate micro-misregistration, vibrant energy",
            "Artisanal screenprint, metallic warm bronze and deep slate inks on heavyweight cotton paper, elegant handcrafted texture",
            "Graphic art print with layered stencil textures, bold shapes, warm paper background, modern gallery feel",
        ],
        "swiss_minimalist_and_geometric": [
            "Modern Swiss-style graphic design, rigorous grid structure, confident asymmetrical negative space, refined color harmony",
            "Minimalist Bauhaus-inspired art poster, harmonious interplay of circle, triangle, and line with subtle paper grain",
            "Constructivist-inspired modern graphic, bold dynamic diagonals, clean geometric forms, strong visual impact",
            "Minimal geometric art, simplified shapes and flat planes, perfectly calibrated color relationships",
            "Clean modern graphic aesthetic, elegant circular motifs, crisp balance, sophisticated contrast",
        ],
    },

    # =========================================================================
    # 5. CRAFT, SCULPTURAL & TACTILE DIORAMAS (20 Styles)
    # =========================================================================
    "craft_and_sculptural_dioramas": {
        "sculpted_papercraft": [
            "Multi-layered cut-paper shadow box, laser-sharp paper layers creating atmospheric depth, backlit with warm ambient glow",
            "Tactile papercraft style, folded-paper forms, soft natural window light, charming handmade feel",
            "Layered colored cardstock paper art, clean dimensional silhouettes casting soft real shadows, bright cheerful colors",
            "Minimalist white paper sculpture on warm toned background, delicate embossed folds, soft directional sidelight",
            "Pop-up book paper sculpture, folded paper mechanisms standing in dynamic three-dimensional relief, joyful discovery",
        ],
        "carved_wood_and_natural_materials": [
            "Hand-carved relief wood sculpture, expressive chisel marks, polished beeswax finish, warm natural woodgrain",
            "Modern wooden tabletop miniature, smooth oak and brass accents, clean geometric silhouettes, warm studio light",
            "Scandinavian folk wood carving, stylized decorative motifs, painted accents, honest handcrafted warmth",
            "Tactile felt and fabric miniature scene, soft fuzzy wool textures, warm visible stitches, comforting handmade feel",
            "Turned wooden architectural model, smooth beech and brass details, clean geometric forms, warm studio light",
        ],
        "stop_motion_and_miniature_rooms": [
            "Artisan miniature craftsmanship, tiny meticulous details, realistic warm brass accents, lamplit glow",
            "Whimsical stop-motion look, tiny hand-crafted props, visible handmade imperfections, cozy sunbeam glow",
            "Woven textile tapestry art, richly textured threads, soft natural-dye colors, warm handcrafted depth",
            "Mosaic art made of small glazed tiles, luminous color facets, fine grout lines, warm sunlit sheen",
            "Wes Anderson-inspired symmetrical miniature set, pastel palette, meticulous prop organization, charming deadpan whimsy",
        ],
        "ceramic_glass_and_dimensional_art": [
            "Ink-wash painting on rice paper, fluid expressive brushwork, graduated tonal washes, generous negative space, delicate touches of color",
            "Handcrafted ceramic sculpture, smooth tactile stoneware, soft matte glaze in warm earthy tones, gentle studio lighting",
            "Stained glass panel art, jewel-toned textured glass held by lead lines, casting vibrant colored sunlight across the frame",
            "Translucent sculpted resin art, suspended colorful gradients capturing and refracting soft daylight, clean modern aesthetic",
            "Modern mixed-media shadowbox assemblage, harmonious blend of tactile wood, paper, and matte ceramics, gallery presentation",
        ],
    },

    # =========================================================================
    # 6. FUTURISTIC, MYSTICAL & ORNAMENTAL (7 Styles)
    # =========================================================================
    "futuristic_mystical_and_ornamental": {
        "neon_and_futuristic": [
            "Neon-noir cyberpunk illustration, saturated magenta and cyan glow against deep shadow, rain-slick reflective surfaces, volumetric haze, holographic light accents",
            "Retro synthwave poster aesthetic, glowing gradient palette of violet, pink and electric blue, soft grid-line glow, bold airbrushed light",
            # Longer than the others on purpose: with only keywords, "holographic" came out as an ordinary photo with a few shiny cups.
            "Iridescent holographic art, shifting pearl and oil-slick color gradients, glossy translucent surfaces, soft prismatic light. "
            "Picture the shifting rainbow sheen of holographic foil or a soap-bubble film, where color changes with the angle of view. "
            "Let that iridescence reach the whole image, not just a few objects: surfaces, light, and even the air carry pearly, "
            "color-shifting gradients, while the scene itself stays clear and readable. It should read as a polished digital artwork, "
            "not an ordinary photograph with a few shiny things in it.",
        ],
        "cosmic_and_ethereal": [
            "Cosmic digital painting, deep indigo and violet nebula gradients, drifting luminous stardust, soft cosmic glow, painterly depth",
            "Bioluminescent dreamscape, soft glowing particles in deep teal darkness, ethereal haze, delicate living-light accents",
            "Long-exposure ethereal photograph, silky light trails, soft aurora-like green and violet glow, hushed night atmosphere",
        ],
        "ornamental_and_decorative": [
            "Art Nouveau ornamental illustration, flowing organic linework, gilded accents on muted jewel tones, elegant decorative rhythm",
        ],
    },
}


# Flattened list of all styles
ALL_ART_STYLES: List[str] = [
    style
    for cat_dict in ART_STYLES_BY_CATEGORY.values()
    for subcat_list in cat_dict.values()
    for style in subcat_list
]


def pick_art_style() -> str:
    """
    Pick the one style a lecture's whole image series is drawn in.

    The system decides, not the LLM: left to choose, GPT-6-Luna converges on the same
    medium every time (papercraft, and gouache once papercraft is banned), so variety
    across a student's lectures cannot come from asking the model for it.
    """
    return random.choice(ALL_ART_STYLES)

