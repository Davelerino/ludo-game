shader_type spatial;
render_mode cull_front, unshaded, depth_draw_opaque;

// Contour "inverted hull" : à brancher en `next_pass` du ShaderMaterial
// stylized_toon.gdshader pour un liseré sombre autour de chaque élément.
// Le mesh est extrudé le long de ses normales puis rendu de l'intérieur
// (cull_front), ce qui ne laisse dépasser que la bordure derrière le mesh
// d'origine.

uniform vec4 outline_color : source_color = vec4(0.05, 0.05, 0.08, 1.0);
uniform float outline_width : hint_range(0.0, 0.05) = 0.012;

void vertex() {
	VERTEX += NORMAL * outline_width;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = outline_color.a;
}
