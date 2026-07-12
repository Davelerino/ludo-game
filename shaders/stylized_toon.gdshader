shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_disabled;

// Shader "stylized/toon" générique : une seule et même passe sert pour tous
// les éléments (pions, cases d'anneau, couloirs finaux...). Seule la couleur
// change d'un élément à l'autre, via `albedo_color` — dupliquer ce
// ShaderMaterial (Inspector > clic droit > "Make Unique") ou appeler
// mesh_instance.set_instance_shader_parameter("albedo_color", couleur) pour
// varier la teinte sans dupliquer le shader ni le matériau.

uniform vec4 albedo_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D albedo_texture : source_color, filter_nearest;

uniform int band_count : hint_range(2, 6) = 3;
uniform vec4 shadow_color : source_color = vec4(0.35, 0.37, 0.5, 1.0);

uniform vec4 rim_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float rim_amount : hint_range(0.0, 2.0) = 0.4;
uniform float rim_threshold : hint_range(0.0, 1.0) = 0.7;

uniform float specular_size : hint_range(1.0, 128.0) = 32.0;
uniform float specular_intensity : hint_range(0.0, 1.0) = 0.35;


void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	ALBEDO = albedo_color.rgb * tex.rgb;
	ALPHA = albedo_color.a * tex.a;

	// Rim light (contour lumineux) : renforce la lisibilité des silhouettes,
	// utile pour distinguer les pions par-dessus le plateau.
	float rim_dot = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim_mask = smoothstep(rim_threshold - 0.05, rim_threshold + 0.05, rim_dot) * rim_amount;
	EMISSION = rim_color.rgb * rim_mask;
}


void light() {
	// Bande la lumière reçue en `band_count` paliers discrets (cel-shading)
	// au lieu du dégradé continu du diffuse standard.
	float n_dot_l = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float banded = ceil(n_dot_l * float(band_count)) / float(band_count);
	vec3 tone = mix(shadow_color.rgb, vec3(1.0), banded);
	DIFFUSE_LIGHT += ALBEDO * tone * LIGHT_COLOR * ATTENUATION;

	// Reflet spéculaire "toon" : un point net plutôt qu'un halo progressif.
	vec3 halfway = normalize(LIGHT + VIEW);
	float n_dot_h = clamp(dot(NORMAL, halfway), 0.0, 1.0);
	float spec = smoothstep(0.98, 1.0, pow(n_dot_h, specular_size)) * specular_intensity;
	SPECULAR_LIGHT += spec * LIGHT_COLOR * ATTENUATION;
}
