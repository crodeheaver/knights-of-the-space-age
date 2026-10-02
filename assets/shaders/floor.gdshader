shader_type spatial;
// Deck plating: vertex colour base with world-space panel seams.
uniform float panel = 2.0;
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 g = abs(fract(wpos.xz / panel) - 0.5);
	float seam = smoothstep(0.465, 0.49, max(g.x, g.y));
	vec2 g2 = abs(fract(wpos.xz / (panel * 0.5)) - 0.5);
	float sub = smoothstep(0.48, 0.495, max(g2.x, g2.y)) * 0.35;
	vec3 base = COLOR.rgb;
	ALBEDO = mix(base, base * 0.45, max(seam, sub));
	ROUGHNESS = 0.75;
	METALLIC = 0.25;
}
