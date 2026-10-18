// 시뮬레이터 전용 보충 파일.
// 아이폰 본체의 Metal에는 있지만 iOS 시뮬레이터의 Metal에는 없는 상수들.
// Godot 라이브러리(metal_cpp)가 이 이름을 찾기 때문에 시뮬레이터 빌드에서만 채워 준다.
#import <Foundation/Foundation.h>

NSString *const MTLIOErrorDomain = @"MTLIOErrorDomain";
NSString *const MTLTensorDomain = @"MTLTensorDomain";
