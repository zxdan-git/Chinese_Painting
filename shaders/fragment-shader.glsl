
varying vec2 vUvs;

uniform vec2 resolution;
uniform float time;

const float HEIGHT = 1000.0;
const int MAX_CPS = 10;
const int BRANCH_DEPTH = 4;
const int MAX_BRANCH = 100;
const float GROUND_LEVEL = 200.0;
const float TRUNK_HEIGHT = 400.0;

const float EPSILON = 1e-9;
const float INF = 1e30;
const float PI = 3.14159265358979323846;

const vec3 RED = vec3(1.0, 0.0, 0.0);
const vec3 BLUE = vec3(0.0, 0.0, 1.0);
const vec3 WHITE = vec3(1.0, 1.0, 1.0);
const vec3 BLACK = vec3(0.0, 0.0, 0.0);
const vec3 YELLOW = vec3(1.0, 1.0, 0.0);
const vec3 PAPER_COLOR = vec3(1.0);

const float TRUNK_TIME = 2.0;
const float BRANCH_TIME = 2.0;
const float FLOWER_TIME = 1.0;

const int FLOWER_NUM = 10;

vec2 toPixel(vec2 uv) {
  float width = resolution.x * HEIGHT / resolution.y; 
  return uv * vec2(width, HEIGHT) - vec2(0.0, GROUND_LEVEL);
}

// Noise functions.
vec3 hash( vec3 p ) {
	p = vec3( dot(p,vec3(127.1,311.7, 74.7)),
            dot(p,vec3(269.5,183.3,246.1)),
            dot(p,vec3(113.5,271.9,124.6)));

	return -1.0 + 2.0*fract(sin(p)*43758.5453123);
}

float noise( in vec3 p ) {
  vec3 i = floor( p );
  vec3 f = fract( p );
	
	vec3 u = f*f*(3.0-2.0*f);

  return mix( mix( mix( dot( hash( i + vec3(0.0,0.0,0.0) ), f - vec3(0.0,0.0,0.0) ), 
                        dot( hash( i + vec3(1.0,0.0,0.0) ), f - vec3(1.0,0.0,0.0) ), u.x),
                   mix( dot( hash( i + vec3(0.0,1.0,0.0) ), f - vec3(0.0,1.0,0.0) ), 
                        dot( hash( i + vec3(1.0,1.0,0.0) ), f - vec3(1.0,1.0,0.0) ), u.x), u.y),
              mix( mix( dot( hash( i + vec3(0.0,0.0,1.0) ), f - vec3(0.0,0.0,1.0) ), 
                        dot( hash( i + vec3(1.0,0.0,1.0) ), f - vec3(1.0,0.0,1.0) ), u.x),
                   mix( dot( hash( i + vec3(0.0,1.0,1.0) ), f - vec3(0.0,1.0,1.0) ), 
                        dot( hash( i + vec3(1.0,1.0,1.0) ), f - vec3(1.0,1.0,1.0) ), u.x), u.y), u.z );
}

float fbm(vec3 p, int octaves, float persistence, float lacunarity) {
  float amplitude = 1.0;
  float frequency = 1.0;
  float total = 0.0;
  float normalization = 0.0;

  for (int i = 0; i < octaves; ++i) {
    float noiseValue = noise(p * frequency);
    total += noiseValue * amplitude;
    normalization += amplitude;
    amplitude *= persistence;
    frequency *= lacunarity;
  }

  total /= normalization;
  total = smoothstep(-1.0, 1.0, total);

  return total;
}

// Math functions.
mat3 rotate(float angle) {
  float s = sin(angle);
  float c = cos(angle);
  return mat3(c, s, 0.0, -s, c, 0.0, 0.0, 0.0, 1.0);
}

float cbrt(float x) {
    return sign(x) * pow(abs(x), 1.0 / 3.0);
}

int linearSolver(float a, float b, out float root) {
  root = 0.0;
  if(abs(a) <  EPSILON) {
    return 0;
  }
  root = -b / a;
  return 1;
}

int quadraticSolver(float a, float b, float c, out float root1, out float root2) {
  root1 = 0.0;
  root2 = 0.0;
  if(abs(a) <  EPSILON) {
    return linearSolver(b, c, root1);
  }
  float d = b * b - 4.0 * a * c;
  if(d < -EPSILON) {
    return 0;
  } 
  
  if (d < EPSILON) {
    root1 = -b / (2.0 * a);
    return 1;
  } 
  
  float sqrtD = sqrt(d);
  root1 = (-b + sqrtD) / (2.0 * a);
  root2 = (-b - sqrtD) / (2.0 * a);
  return 2;
}

int cubicSolver(float a, float b, float c, float d, out float root1, out float root2, out float root3) {
  root1 = 0.0;
  root2 = 0.0;
  root3 = 0.0;
  if(abs(a) < EPSILON) {
    return quadraticSolver(b, c, d, root1, root2);
  }

  // Depressed cubic: t^3 + pt + q = 0 via x = t - b / (3a)
  float inv_a = 1.0 / a;
  b *= inv_a;
  c *= inv_a;
  d *= inv_a;

  float shift = b / 3.0;
  float p = c - shift * b;
  float q = (2.0 * b * b * b - 9.0 * b * c) / 27.0 + d;

  // Half-discriminant D = (q/2)^2 + (p/3)^3
  float p_over_3 = p / 3.0;
  float q_over_2 = q / 2.0;
  float D = q_over_2 * q_over_2 + p_over_3 * p_over_3 * p_over_3;

  if (D > EPSILON) {
    // One real root, two complex conjugate roots (Cardano's method)
    float sqrt_D = sqrt(D);
    float u = cbrt(-q_over_2 + sqrt_D);
    float v = cbrt(-q_over_2 - sqrt_D);
    root1 = (u + v) - shift;
    return 1;
  } 
  
  if (abs(D) <= EPSILON) {
    // Real roots with multiplicity
    float u = cbrt(-q_over_2);
    root1 = 2.0 * u - shift;
    root2 = -u - shift;
    if (abs(root1 - root2) < EPSILON) {
      return 1;
    }
    return 2;
  }
      
  // Three distinct real roots (Viète's trigonometric method)
  // Clamp input to acos to [-1.0, 1.0] to prevent NaN from precision limits
  float phi = acos(clamp(-q_over_2 / sqrt(-p_over_3 * p_over_3 * p_over_3), -1.0, 1.0));
  float factor = 2.0 * sqrt(-p_over_3);

  root1 = factor * cos(phi / 3.0) - shift;
  root2 = factor * cos((phi + 2.0 * PI) / 3.0) - shift;
  root3 = factor * cos((phi + 4.0 * PI) / 3.0) - shift;
  return 3;
}

vec2 bezier(vec2 p1, vec2 p2, vec2 p3, float t) {
  return p1 * (1.0 - t) * (1.0 - t) + p2 * 2.0 * t * (1.0 - t) + p3 * t * t;
}

vec2 curve(vec2 cps[MAX_CPS], int cpNum, float t) {
  if(cpNum < 3) {
    return vec2(0.0);
  }
  t = t * float(cpNum - 2);
  int idx = 3 + int(floor(t));
  float ti = fract(t);
  if(idx == 3) {
    return bezier(cps[0], cps[1], cps[2], ti);
  }

  vec2 cp = 1.8 * cps[idx - 2] - 0.8 * cps[idx - 3];
  return bezier(cps[idx - 2], cp, cps[idx - 1], ti);
}

float remap(float x, float inMin, float inMax, float outMin, float outMax) {
  return mix(outMin, outMax, (x - inMin) / (inMax - inMin));
}

// SDF functions.
float sdfBezier(vec2 p, vec2 p1, vec2 p2, vec2 p3, out float t) {
    t = 0.0;
    vec2 alpha = p1 - 2.0 * p2 + p3;
    vec2 beta = 2.0 * (p2 - p1);
    vec2 gamma = p1 - p;

    float a = 2.0 * dot(alpha, alpha);
    float b = 3.0 * dot(alpha, beta);
    float c = 2.0 * dot(alpha, gamma) + dot(beta, beta);
    float d = dot(beta, gamma);

    
    float[] ts = float[3](0.0, 0.0, 0.0);
    int rootNum = cubicSolver(a, b, c, d, ts[0], ts[1], ts[2]);

    float dist = INF;
    for(int i = 0; i < rootNum; i++) {
      float ti = clamp(ts[i], 0.0, 1.0);
      float dt = length(alpha * ti * ti + beta * ti + gamma);
      if(dt < dist) {
        dist = dt;
        t = ti;
      }
    }

    return dist;
}

float sdfCurve(vec2 p, vec2 cps[MAX_CPS], int cpNum, out float t) {
  float dist = INF;
  t = 0.0;
  if (cpNum < 3 || cpNum > MAX_CPS) {
    return dist;
  }

  for(int i = 3; i <= cpNum; i++) {
    float di = INF;
    float ti = 0.0;
    if(i == 3) {
      di = sdfBezier(p, cps[0], cps[1], cps[2], ti);
    } else {
      vec2 cp = 1.8 * cps[i - 2] - 0.8 * cps[i - 3];
      di = sdfBezier(p, cps[i - 2], cp, cps[i - 1], ti);
    }

    if(di < dist) {
      dist = di;
      t = (float(i) - 3.0 + ti) / (float(cpNum) - 2.0);
    }
  }
  return dist;
}

float sdfLine(vec2 p, vec2 p1, vec2 p2) {
  vec2 v = p - p2;
  vec2 v1 = p1 - p2;
  float v1Len = length(v1);
  float proj = dot(v, v1) / v1Len;
  vec2 perp = v - clamp(proj, 0.0, v1Len) * v1 / v1Len;
  return length(perp);
}

float sdfCircle(vec2 p, float r)
{
    return length(p) - r;
}

// Scene.
vec3 background() {
  vec2 distCenter = abs(vUvs - 0.5);
  vec2 bgValue = smoothstep(0.8, 0.0, distCenter);
  vec3 bgColor = mix(BLACK, PAPER_COLOR, bgValue.x) * 0.5;
  bgColor += mix(BLACK, PAPER_COLOR, bgValue.y) * 0.5;
  return bgColor;
}

vec3 flower(vec2 p, float startTime, vec3 color) {
  float d1 = sdfCircle(p - vec2(-4.0, 4.0), 6.0);
  float d2 = sdfCircle(p - vec2(4.0, 4.0), 6.0);
  float d3 = sdfCircle(p - vec2(4.0, -4.0), 6.0);
  float d4 = sdfCircle(p - vec2(-4.0, -4.0), 6.0);

  float timer = smoothstep(startTime, startTime + FLOWER_TIME, time);
  vec3 flowerColor = mix(color, RED, timer);
  color = mix(flowerColor, color, step(0.0, max(d1, d2)));
  color = mix(flowerColor, color, step(0.0, max(d2, d3)));
  color = mix(flowerColor, color, step(0.0, max(d3, d4)));
  color = mix(flowerColor, color, step(0.0, max(d4, d1)));
  return color;
}

vec3 trunk(vec2 p, vec3 color) {
  if(p.y < 0.0) {
    return color;
  }
  vec2 cps[MAX_CPS];
  cps[0] = vec2(0.0, 0.0);
  cps[1] = vec2(20.0, TRUNK_HEIGHT * 0.25);
  cps[2] = vec2(-20.0, TRUNK_HEIGHT * 0.5);
  cps[3] = vec2(0.0, TRUNK_HEIGHT);

  float t = 0.0;
  float ld = sdfCurve(p, cps, 4, t);
  float width = 120.0 * (1.0 - t) + 40.0 * t + noise(vec3(t)) * 20.0;

  float timer = smoothstep(0.0, TRUNK_TIME, time);
  width *= smoothstep(t, 1.0, timer + 0.001);
  float ldValue = step(width, ld);
  color = mix(BLACK, color , ldValue);
  return color;
}

vec3 branch(vec2 p, vec2 cps[MAX_CPS], int cpNum, float startWidth, vec3 startColor, float startTime, vec3 color) {
  float t = 0.0;
  float ld = sdfCurve(p, cps, cpNum, t);
  float width = startWidth * (1.0 - t) + (t * 0.5 + noise(vec3(t))) * startWidth * 0.5;
  float timer = smoothstep(startTime, startTime + BRANCH_TIME, time);
  width *= smoothstep(t, 1.0, timer + 0.001);
  float ldValue = smoothstep(0.8 * width, width, ld);
  color = mix(mix(startColor, vec3(0.4), t), color , ldValue);
  
  vec3 rand = hash(vec3(cps[cpNum - 1], 1.0));
  for(int i = 0; i < int(mix(2.0, 4.0, remap(rand.x, -1.0, 1.0, 0.0, 1.0))); i++) {
    vec3 randi = hash(vec3(cps[cpNum - 1], float(i)));
    float tFlower = remap(randi.x, -1.0, 1.0, 0.5, 1.0);
    float angleFlower = PI * remap(randi.y, -1.0, 1.0, 0.0, 1.0);
    float scaleFlower = mix(2.0, 3.0, remap(randi.z, -1.0, 1.0, 0.0, 1.0));
    float flowerTime = startTime + BRANCH_TIME * tFlower;
    vec2 flowerPos = curve(cps, cpNum, tFlower);
    color = flower((rotate(angleFlower) * vec3(p - flowerPos, 1.0)).xy / scaleFlower, flowerTime, color);
  }
  return color;
}

vec3 tree(vec2 p, vec3 color) {
  float screenWidth = HEIGHT * resolution.x / resolution.y;
  float trunk_x = screenWidth * 0.5;
  color = trunk(p - vec2(trunk_x, 0.0), color);
  for(int i = 0; i < 5; i++) {
    vec2 ori = vec2(trunk_x, TRUNK_HEIGHT);
    vec3 rand = hash(vec3(ori, float(i)));
    float ti = remap(rand.x, -1.0, 1.0, 0.0, 1.0);
    float xRange = 50.0;
    float yRange = mix(400.0, 500.0, ti);
    float angle = mix(-PI/3.0, PI/3.0, float(i) / 4.0);
    vec2 cps[MAX_CPS];
    cps[0] = vec2(0.0);
    cps[1] = vec2(xRange * rand.x, 0.25 * yRange);
    cps[2] = vec2(xRange * rand.y, 0.5 * yRange);
    cps[3] = vec2(xRange * rand.z, yRange);

    vec2 pi = (rotate(angle) * vec3((p - ori), 1.0)).xy;
    vec3 color_i = mix(vec3(0.0), vec3(0.4), ti);
    float time_i = TRUNK_TIME;
    color = branch(pi, cps, 4, 40.0, color_i, time_i, color);
    for(int j = 0; j < 5; j++) {
      rand = hash(vec3(ori, float(i + j)));
      float tj = remap(rand.x, -1.0, 1.0, 0.2, 0.8);
      ori = curve(cps, 4, tj);
      xRange = 20.0;
      yRange = 0.6 * mix(300.0, 400.0, smoothstep(0.0, 0.6, 0.8 - tj));
      angle = mix(-PI/2.0, PI/2.0, remap(rand.y,-1.0, 1.0, 0.0, 1.0));
      vec2 cpsj[MAX_CPS];
      cpsj[0] = vec2(0.0);
      cpsj[1] = vec2(xRange * rand.x, 0.25 * yRange);
      cpsj[2] = vec2(xRange * rand.y, 0.5 * yRange);
      cpsj[3] = vec2(xRange * rand.z, yRange);
      float wj = 40.0 * (1.0 - tj) * 1.0;

      vec2 pj = (rotate(angle) * vec3((pi - ori), 1.0)).xy;
      vec3 color_j = mix(color_i, vec3(0.4), ti);
      float time_j = time_i + BRANCH_TIME * tj;
      color = branch(pj, cpsj, 4, wj, color_j, time_j, color);
      for(int k = 0; k < 1; k ++) {
        rand = hash(vec3(ori, float(i + j + k)));
        float tk = remap(rand.x, -1.0, 1.0, 0.1, 0.6);
        ori = curve(cpsj, 4, tk);
        xRange = 20.0;
        yRange = 0.36 * mix(300.0, 400.0, smoothstep(0.0, 0.5, 0.6 - tk));
        angle = mix(-PI/2.0, PI/2.0, remap(rand.y,-1.0, 1.0, 0.0, 1.0));
        vec2 cpsk[MAX_CPS];
        cpsk[0] = vec2(0.0);
        cpsk[1] = vec2(xRange * rand.x, 0.25 * yRange);
        cpsk[2] = vec2(xRange * rand.y, 0.5 * yRange);
        cpsk[3] = vec2(xRange * rand.z, yRange);
        float wk = wj * (1.0 - tk);

        vec2 pk = (rotate(angle) * vec3((pj - ori), 1.0)).xy;
        vec3 color_k = mix(color_j, vec3(0.4), tk);
        float time_k = time_j + BRANCH_TIME;
        color = branch(pk, cpsk, 4, wk, color_k, time_k, color);
      }
    }
  }
  return color;
}

vec3 flowerRain(vec2 p, vec3 color) {
  if(time < 5.0) {
    return color;
  }

  float screenWidth = HEIGHT * resolution.x / resolution.y;
  float trunk_x = screenWidth * 0.5;
  for(int i = 0; i < FLOWER_NUM; i ++) {
    vec3 rand = hash(vec3(float(i)));
    float x = rand.x * 500.0 + trunk_x;
    float y = remap(rand.y, -1.0, 1.0, TRUNK_HEIGHT, HEIGHT * 0.9);
    float t = remap(sin(time * 2.0 * PI * 0.02 - 0.2 * PI), -1.0, 1.0, 0.0, 1.0);
    float t_fract = fract(time * 0.02 - 0.1);
    if((t_fract > 0.25 && t_fract < 0.75)) {
      t = 1.0 - t;
    }
    y = y * (1.0 - t) + remap(rand.x, -1.0, 1.0, -50.0, -100.0) * t;
    if(y < 0.0) {
      y = 0.0;
      
    } 
    x = (x + remap(rand.z, -1.0, 1.0, 0.0, 100.0)) * t + x * (1.0 - t);
    float scale = remap(rand.z, -1.0, 1.0, 1.0, 3.0);
    color = flower((rotate(2.0 * PI * t) * vec3((p - vec2(x, y)), 1.0)).xy / scale, 0.0, color);
  }
  return color;
}

vec3 mountain(vec2 p, vec3 color) {
  float y = fbm(
    vec3(p.x / 256.0, 1.432, 3.643), 6, 0.5, 2.0) * 256.0 + 250.0;
  float d = p.y - y;
  vec3 color1 = mix(BLACK, color, smoothstep(0.0, 10.0, d));
  vec3 color2 = mix(vec3(0.7), color, smoothstep(0.0, -50.0, d));
  return color1 + color2;
}

vec3 scene(vec2 p, vec3 color) {
  color = mountain(p, color);
  color = tree(p, color);
  color = flowerRain(p, color);
  return color;
}

void main() {
  vec2 p = toPixel(vUvs);
  vec3 color = background();
  
  if(p.y > 0.0) {
    color = scene(p - vec2(0.0, 1.0), color);
  } else {
    color = scene(vec2(p.x, -2.0 * remap(sin(p.y / 10.0 + time), -1.0, 1.0, -GROUND_LEVEL, 0.0)), color);
  }

  gl_FragColor = vec4(color, 1.0);
}
