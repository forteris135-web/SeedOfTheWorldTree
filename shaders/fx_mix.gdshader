shader_type canvas_item;
// 이펙트 그림 (보통 섞기). 빛을 받지 않는다(unshaded): 어두운 방(CanvasModulate)에서도 이펙트는 제 밝기로 보인다.
render_mode blend_mix, unshaded;
#include "res://shaders/fx.gdshaderinc"
