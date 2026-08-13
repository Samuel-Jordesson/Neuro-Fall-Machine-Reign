shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never;

// Anel de rastro que fica na agua quando algo se mexe nela.
// O tamanho e a opacidade vem de progress, que o water.gd anima por codigo.

uniform vec4 ring_color : source_color = vec4(0.85, 0.95, 1.0, 1.0);
uniform float ring_thickness : hint_range(0.02, 0.5) = 0.14;

// Mesmos parametros de onda do water.gdshader. O water.gd copia os valores da
// agua para ca, senao o anel afunda dentro da crista da onda e some.
uniform sampler2D wave;
uniform sampler2D wave2;
uniform vec2 wave_dir = vec2(1.0, 0.5);
uniform vec2 wave_dir2 = vec2(-0.5, 1.0);
uniform float time_scale = 0.03;
uniform float wave_scale = 0.2;
uniform float wave_height = 0.3;

// 0 = anel acabou de nascer no centro, 1 = anel grande e ja apagado.
instance uniform float progress = 0.0;
instance uniform float strength = 1.0;

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 uv1 = world_pos.xz * wave_scale + TIME * wave_dir * time_scale;
	vec2 uv2 = world_pos.xz * wave_scale + TIME * wave_dir2 * time_scale;
	float w = texture(wave, uv1).r + texture(wave2, uv2).r;
	VERTEX.y += w * wave_height;
}

void fragment() {
	float d = distance(UV, vec2(0.5)) * 2.0;

	// Anel fino que caminha do centro pra borda conforme progress cresce.
	float ring = smoothstep(ring_thickness, 0.0, abs(d - progress));

	// Um segundo anel mais fraco atras, pra dar cara de ondulacao e nao de aro.
	float trail = smoothstep(ring_thickness * 2.0, 0.0, abs(d - progress * 0.55)) * 0.35;

	float fade = (1.0 - progress) * strength;
	float mask = 1.0 - smoothstep(0.85, 1.0, d);

	ALBEDO = ring_color.rgb;
	ALPHA = (ring + trail) * fade * mask * ring_color.a;
}
