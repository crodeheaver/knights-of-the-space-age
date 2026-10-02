shader_type spatial;
// Bulkhead panels: horizontal bands and vertical seams in world space.
varying vec3 wpos;
varying vec3 wnorm;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	vec3 base = COLOR.rgb;
	float along = abs(wnorm.x) > 0.5 ? wpos.z : wpos.x;
	float vseam = smoothstep(0.47, 0.49, abs(fract(along / 1.5) - 0.5));
	float band = step(wpos.y, 0.25) * 0.5 + step(2.35, wpos.y) * step(wpos.y, 2.5) * 0.6;
	float top = step(3.15, wpos.y);
	vec3 c = mix(base, base * 0.55, max(vseam * step(0.25, wpos.y), band));
	c = mix(c, base * 1.35, top);
	ALBEDO = c;
	ROUGHNESS = 0.8;
	METALLIC = 0.15;
}
