shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 albedo : source_color = vec3(0.0, 0.32, 0.43);
uniform vec3 albedo2 : source_color = vec3(0.0, 0.45, 0.55);
uniform vec3 foam_color : source_color = vec3(1.0, 1.0, 1.0);

uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.02;

uniform sampler2D wave;
uniform sampler2D wave2;
uniform sampler2D normalmap : hint_normal;

uniform vec2 wave_dir = vec2(1.0, 0.5);
uniform vec2 wave_dir2 = vec2(-0.5, 1.0);
uniform float time_scale : hint_range(0.0, 0.2, 0.005) = 0.03;

uniform float wave_scale = 0.2;
uniform float wave_height = 0.15;

uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_linear_mipmap;

uniform float edge_scale = 0.5;

varying float height;
varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	vec2 uv1 = world_pos.xz * wave_scale + TIME * wave_dir * time_scale;
	vec2 uv2 = world_pos.xz * wave_scale + TIME * wave_dir2 * time_scale;
	
	float w1 = texture(wave, uv1).r;
	float w2 = texture(wave2, uv2).r;
	
	height = (w1 + w2) * wave_height;
	VERTEX.y += height;
}

void fragment() {
	// Depth edge foam
	float depth = texture(DEPTH_TEXTURE, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float linear_depth = -view.z;
	float surface_depth = -VERTEX.z;
	
	float depth_diff = linear_depth - surface_depth;
	
	// Create stylized foam
	vec2 uv1 = world_pos.xz * wave_scale + TIME * wave_dir * time_scale;
	vec2 uv2 = world_pos.xz * wave_scale + TIME * wave_dir2 * time_scale;
	
	float noise = texture(wave, uv1 * 2.0).r;
	float foam = 1.0 - smoothstep(0.0, edge_scale, depth_diff);
	foam = step(0.4, foam * noise + foam * 0.5);
	
	vec3 n1 = texture(normalmap, uv1).rgb * 2.0 - 1.0;
	vec3 n2 = texture(normalmap, uv2).rgb * 2.0 - 1.0;
	vec3 n = normalize(n1 + n2);
	
	vec3 color = mix(albedo, albedo2, clamp(height / (wave_height * 2.0), 0.0, 1.0));
	vec3 final_color = mix(color, foam_color, foam);
	
	ALBEDO = final_color;
	METALLIC = metallic;
	ROUGHNESS = roughness;
	NORMAL_MAP = n * 0.5 + 0.5;
	ALPHA = mix(0.9, 1.0, foam);
}
