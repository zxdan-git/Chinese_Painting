
varying vec2 vUvs;

uniform vec2 resolution;
uniform float time;

const float HEIGHT = 1000.0;
const int MAX_CPS = 10;
const int BRANCH_DEPTH = 4;
const int MAX_BRANCH = 100;
const float GROUND_LEVEL = 200.0;
const float TRUNK_HEIGHT = 300.0;
const float TRUNK_START_WIDTH = 100.0;
const float TRUNK_END_WIDTH = 40.0;
const float MAIN_BRANCH_LENGTH = 400.0;
const float INK_SIZE = 10.0;

const float EPSILON = 1e-9;
const float INF = 1e30;
const float PI = 3.14159265358979323846;

const vec2 LIGHT_POS = vec2(0.0, HEIGHT);

const vec3 RED = vec3(1.0, 0.0, 0.0);
const vec3 PINK = vec3(1.0, 0.4, 0.4);
const vec3 BLUE = vec3(0.0, 0.0, 1.0);
const vec3 WHITE = vec3(1.0, 1.0, 1.0);
const vec3 BLACK = vec3(0.0, 0.0, 0.0);
const vec3 YELLOW = vec3(1.0, 1.0, 0.0);
const vec3 PAPER_COLOR = vec3(1.0);

const float INK_TIME = 3.0;
const float TRUNK_TIME = 1.0;
const float BRANCH_TIME = 2.0;
const float FLOWER_TIME = 1.0;
const float FLOWER_RAIN_TIME = 3.0;

const int FLOWER_NUM = 20;

struct BranchInfo {
  vec2 localPosition;
  vec2 controlPoints[MAX_CPS];
  int controlPointsNum;
  float startWidth;
  vec3 startColor;
  float startTime;
  vec3 seed;
  int depth;
  vec2 lightLocalPos;
};

vec2 toPixel(vec2 uv) {
  float width = resolution.x * HEIGHT / resolution.y;
  return uv * vec2(width, HEIGHT) - vec2(width * 0.5, GROUND_LEVEL);
}

// Noise functions.
vec3 hash(vec3 p) {
  p = vec3(dot(p, vec3(127.1, 311.7, 74.7)), dot(p, vec3(269.5, 183.3, 246.1)),
           dot(p, vec3(113.5, 271.9, 124.6)));

  return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

float noise(in vec3 p) {
  vec3 i = floor(p);
  vec3 f = fract(p);

  vec3 u = f * f * (3.0 - 2.0 * f);

  return mix(
      mix(mix(dot(hash(i + vec3(0.0, 0.0, 0.0)), f - vec3(0.0, 0.0, 0.0)),
              dot(hash(i + vec3(1.0, 0.0, 0.0)), f - vec3(1.0, 0.0, 0.0)), u.x),
          mix(dot(hash(i + vec3(0.0, 1.0, 0.0)), f - vec3(0.0, 1.0, 0.0)),
              dot(hash(i + vec3(1.0, 1.0, 0.0)), f - vec3(1.0, 1.0, 0.0)), u.x),
          u.y),
      mix(mix(dot(hash(i + vec3(0.0, 0.0, 1.0)), f - vec3(0.0, 0.0, 1.0)),
              dot(hash(i + vec3(1.0, 0.0, 1.0)), f - vec3(1.0, 0.0, 1.0)), u.x),
          mix(dot(hash(i + vec3(0.0, 1.0, 1.0)), f - vec3(0.0, 1.0, 1.0)),
              dot(hash(i + vec3(1.0, 1.0, 1.0)), f - vec3(1.0, 1.0, 1.0)), u.x),
          u.y),
      u.z);
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
  if (abs(a) < EPSILON) {
    return 0;
  }
  root = -b / a;
  return 1;
}

int quadraticSolver(float a,
                    float b,
                    float c,
                    out float root1,
                    out float root2) {
  root1 = 0.0;
  root2 = 0.0;
  if (abs(a) < EPSILON) {
    return linearSolver(b, c, root1);
  }
  float d = b * b - 4.0 * a * c;
  if (d < -EPSILON) {
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

int cubicSolver(float a,
                float b,
                float c,
                float d,
                out float root1,
                out float root2,
                out float root3) {
  root1 = 0.0;
  root2 = 0.0;
  root3 = 0.0;
  if (abs(a) < EPSILON) {
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
  float phi =
      acos(clamp(-q_over_2 / sqrt(-p_over_3 * p_over_3 * p_over_3), -1.0, 1.0));
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
  if (cpNum == 1) {
    return cps[0];
  }

  if (cpNum == 2) {
    return mix(cps[0], cps[1], t);
  }

  float curveNum = (float(cpNum) - 1.0) * 0.5;
  t = t * curveNum;
  int idx = 2 * int(floor(t));
  float ti = fract(t);
  return bezier(cps[idx], cps[idx + 1], cps[idx + 2], ti);
}

float remap(float x, float inMin, float inMax, float outMin, float outMax) {
  return mix(outMin, outMax, (x - inMin) / (inMax - inMin));
}

vec3 unifyHash(vec3 hashValue) {
  return vec3(remap(hashValue.x, -1.0, 1.0, 0.0, 1.0),
              remap(hashValue.y, -1.0, 1.0, 0.0, 1.0),
              remap(hashValue.z, -1.0, 1.0, 0.0, 1.0));
}

vec2 projOnLine(vec2 p, vec2 p1, vec2 p2, bool clampToSegment) {
  vec2 v = p - p2;
  vec2 v1 = p1 - p2;
  float v1Len = length(v1);
  float proj = dot(v, v1) / v1Len;
  if (clampToSegment) {
    proj = clamp(proj, 0.0, v1Len);
  }
  return proj * v1 / v1Len + p2;
}

void amendControlPoints(inout vec2 controlPoints[MAX_CPS],
                        inout int controlPointsNum) {
  if (controlPointsNum <= 3) {
    return;
  }
  for (int i = controlPointsNum - 1; i >= 3; i--) {
    controlPoints[2 * i - 2] = controlPoints[i];
  }
  controlPointsNum = 2 * controlPointsNum - 3;
  for (int i = 3; i < controlPointsNum - 1; i += 2) {
    vec2 p1 = controlPoints[i - 2];
    vec2 p2 = controlPoints[i - 1];
    vec2 p3 = controlPoints[i + 1];
    vec2 proj = projOnLine(p3, p1, p2, false);
    controlPoints[i] = proj;
  }
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
  for (int i = 0; i < rootNum; i++) {
    float ti = clamp(ts[i], 0.0, 1.0);
    float dt = length(alpha * ti * ti + beta * ti + gamma);
    if (dt < dist) {
      dist = dt;
      t = ti;
    }
  }

  return dist;
}

float sdfLine(vec2 p, vec2 p1, vec2 p2, out float t) {
  vec2 proj = projOnLine(p, p1, p2, true);
  t = length(proj - p1) / length(p2 - p1);
  vec2 perp = p - proj;
  return length(perp);
}

float sdfCircle(vec2 p, float r) {
  return length(p) - r;
}

float sdfCurve(vec2 p, vec2 cps[MAX_CPS], int cpNum, out float t) {
  t = 0.0;
  if (cpNum == 1) {
    return sdfCircle(p - cps[0], 0.0);
  }

  if (cpNum == 2) {
    return sdfLine(p, cps[0], cps[1], t);
  }

  float dist = INF;
  float curveNum = (float(cpNum) - 1.0) * 0.5;
  for (int i = 2; i < cpNum; i += 2) {
    float di = INF;
    float ti = 0.0;
    di = sdfBezier(p, cps[i - 2], cps[i - 1], cps[i], ti);
    if (di < dist) {
      dist = di;
      t = (float(i) * 0.5 - 1.0 + ti) / curveNum;
    }
  }
  return dist;
}

float sdfPetal(vec2 p, float r, float width) {
  float halfWidth = 0.5 * width;
  float h = sqrt(r * r - (r - halfWidth) * (r - halfWidth));
  float d1 = sdfCircle(p - vec2(-r + halfWidth, h), r);
  float d2 = sdfCircle(p - vec2(r - halfWidth, h), r);
  return max(d1, d2);
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
  float d = INF;
  float timer = smoothstep(startTime, startTime + FLOWER_TIME, time);
  for (int i = 0; i < 5; i++) {
    d = min(d, sdfPetal((rotate(float(i) * 0.4 * PI) * vec3(p, 1.0)).xy, 4.0,
                        2.0 * timer));
  }

  color = mix(PINK, color, step(0.0, d));
  color = mix(WHITE, color, smoothstep(-0.8, 0.0, d));
  return color;
}

vec3 trunk(vec2 p, vec3 color) {
  if (p.y < 0.0) {
    return color;
  }
  vec2 cps[MAX_CPS];
  cps[0] = vec2(0.0, 0.0);
  cps[1] = vec2(-0.1 * TRUNK_HEIGHT, TRUNK_HEIGHT * 0.5);
  cps[2] = vec2(0.0, TRUNK_HEIGHT);
  int cpsNum = 3;

  float t = 0.0;
  float ld = sdfCurve(p, cps, cpsNum, t);
  float width = TRUNK_START_WIDTH * (1.0 - t) + TRUNK_END_WIDTH * t;

  float timer = smoothstep(INK_TIME, INK_TIME + TRUNK_TIME, time);
  width *= smoothstep(t, 1.0, timer + 0.001);
  float ldValue = 1.0;
  if (width > 1.0) {
    ldValue = smoothstep(width, width + 5.0, ld);
  }
  color = mix(BLACK, color, ldValue);
  return color;
}

vec3 branch(BranchInfo info, vec3 color) {
  float t = 0.0;
  float ld = sdfCurve(info.localPosition, info.controlPoints,
                      info.controlPointsNum, t);
  float width = info.startWidth * (1.0 - t) + 0.1 * info.startWidth * t;
  float timer = smoothstep(info.startTime, info.startTime + BRANCH_TIME, time);
  width *= smoothstep(t, 1.0, timer);
  float ldValue = smoothstep(0.8 * width, width, ld);
  color = mix(mix(info.startColor, vec3(0.6), t), color, ldValue);
  if (ld <= width) {
    vec2 ori = curve(info.controlPoints, info.controlPointsNum, t);
    float z = sqrt(width * width - ld * ld);
    vec3 normal = normalize(vec3(info.localPosition - ori, z));
    vec3 lightDir =
        vec3(normalize(info.lightLocalPos - info.localPosition), 0.0);
    color = mix(color, PINK, smoothstep(0.2, 1.0, dot(lightDir, normal)));
  }

  vec3 rand = unifyHash(hash(info.seed));
  int flowerNum = int(mix(3.0, 5.0, rand.x));
  for (int i = 0; i < flowerNum; i++) {
    vec3 seedi =
        info.seed + length(info.seed) * vec3(float(i + 1)) / float(flowerNum);
    vec3 randi = unifyHash(hash(seedi));
    float tFlower = mix(0.4, 0.9, randi.x);
    float angleFlower = PI * randi.y;
    float scaleFlower = mix(2.0, 7.0, randi.z);
    float flowerTime = info.startTime + BRANCH_TIME * tFlower;
    vec2 flowerPos = curve(info.controlPoints, info.controlPointsNum, tFlower);
    color = flower(
        (rotate(angleFlower) * vec3(info.localPosition - flowerPos, 1.0)).xy /
            scaleFlower,
        flowerTime, color);
  }
  return color;
}

vec3 buildBranch(BranchInfo info, vec3 color) {
  BranchInfo infos[MAX_BRANCH];
  infos[0] = info;
  int stackTop = 1;
  while (stackTop > 0) {
    info = infos[--stackTop];
    color = branch(info, color);
    if (info.depth == 3) {
      continue;
    }
    float l = length(info.controlPoints[info.controlPointsNum - 1] -
                     info.controlPoints[0]);
    int subNum =
        int(mix(1.0, 5.0, remap(noise(info.seed), -1.0, 1.0, 0.0, 1.0)));
    for (int i = 0; i < subNum; i++) {
      vec3 seedi =
          info.seed + length(info.seed) * vec3(float(i + 1)) / float(subNum);
      vec3 rand = unifyHash(hash(seedi));
      float angle =
          mix(PI / 4.0, PI / 3.0, rand.x) * (2.0 * step(0.5, rand.z) - 1.0);
      float ti = rand.y;
      vec2 ori = curve(info.controlPoints, info.controlPointsNum, ti);
      BranchInfo subInfo;
      subInfo.localPosition =
          (rotate(angle) * vec3(info.localPosition - ori, 1.0)).xy;
      subInfo.lightLocalPos =
          (rotate(angle) * vec3(info.lightLocalPos - ori, 1.0)).xy;
      float li = mix(0.8, 0.2, ti) * l;
      subInfo.controlPoints[0] = vec2(0.0);
      subInfo.controlPoints[1] = vec2(0.0, mix(0.1, 0.5, rand.x) * li);
      subInfo.controlPoints[2] = vec2(mix(0.1, 0.25, rand.z) * sign(angle) * li,
                                      mix(0.5, 0.6, rand.x) * li);
      subInfo.controlPoints[3] =
          vec2(mix(0.0, 0.1, rand.z) * sign(angle) * li, li);
      subInfo.controlPointsNum = 4;
      amendControlPoints(subInfo.controlPoints, subInfo.controlPointsNum);
      subInfo.startWidth =
          info.startWidth * (1.0 - ti) + 0.1 * info.startWidth * ti;
      subInfo.startColor = mix(info.startColor, vec3(0.4), ti);
      subInfo.startTime = info.startTime + BRANCH_TIME * ti;
      subInfo.seed = seedi;
      subInfo.depth = info.depth + 1;
      infos[stackTop++] = subInfo;
    }
  }
  return color;
}

vec3 tree(vec2 p, float maxBranchLen, vec3 color) {
  if (time < INK_TIME) {
    return color;
  }
  color = trunk(p, color);
  for (int i = 0; i < 5; i++) {
    vec2 ori = vec2(0.0, TRUNK_HEIGHT);
    vec3 seedi = vec3(ori, length(ori) * float(i));
    vec3 rand = unifyHash(hash(seedi));
    float angle = mix(-PI / 3.0, PI / 3.0, (float(i) + rand.z) / 5.0);
    float ti = rand.y;
    BranchInfo info;
    info.localPosition = (rotate(angle) * vec3(p - ori, 1.0)).xy;
    info.lightLocalPos = (rotate(angle) * vec3(LIGHT_POS - ori, 1.0)).xy;
    float li = mix(0.8, 1.0, rand.z) * maxBranchLen;
    info.controlPoints[0] = vec2(0.0);
    info.controlPoints[1] = vec2(0.0, mix(0.1, 0.5, rand.x) * li);
    info.controlPoints[2] = vec2(mix(0.1, 0.2, rand.z) * sign(angle) * li,
                                 mix(0.5, 0.6, rand.x) * li);
    info.controlPoints[3] = vec2(mix(0.0, 0.1, rand.z) * sign(angle) * li, li);
    info.controlPointsNum = 4;
    amendControlPoints(info.controlPoints, info.controlPointsNum);
    info.startWidth = TRUNK_END_WIDTH * 0.5;
    info.startColor = BLACK;
    info.startTime = INK_TIME + TRUNK_TIME;
    info.seed = seedi;
    info.depth = 1;
    color = buildBranch(info, color);
  }
  return color;
}

vec3 flowerRain(vec2 p, vec3 color) {
  float screenWidth = HEIGHT * resolution.x / resolution.y;
  float trunk_x = screenWidth * 0.5;
  for (int i = 0; i < FLOWER_NUM; i++) {
    vec3 rand = unifyHash(hash(vec3(float(i * 100)) + 100.0));
    float startTime = mix(0.0, FLOWER_RAIN_TIME, rand.z) + 5.0 + INK_TIME;
    if (time < startTime) {
      continue;
    }
    float x = 0.8 * mix(-MAIN_BRANCH_LENGTH, MAIN_BRANCH_LENGTH, rand.x);
    float y =
        mix(TRUNK_HEIGHT, TRUNK_HEIGHT + 0.5 * MAIN_BRANCH_LENGTH, rand.y);
    vec2 controlPoints[MAX_CPS];
    controlPoints[0] = vec2(x, y);
    controlPoints[1] = vec2(x + mix(0.2, 0.6, rand.x) * MAIN_BRANCH_LENGTH,
                            mix(0.4, 0.6, rand.y) * y);
    controlPoints[2] =
        vec2(x + mix(0.8, 1.0, rand.x) * MAIN_BRANCH_LENGTH, 0.0);
    int controlPointsNum = 3;
    float t = fract((time - startTime) / FLOWER_RAIN_TIME);
    vec2 pos = curve(controlPoints, controlPointsNum, t);
    color = flower((rotate(2.0 * PI * t) * vec3((p - pos), 1.0)).xy / 3.0, 0.0,
                   color);
  }
  return color;
}

vec3 mountain(vec2 p, vec3 color) {
  float y = fbm(vec3(p.x / 256.0, 1.432, 3.643), 6, 0.5, 2.0) * 256.0 + 250.0;
  float d = p.y - y;
  vec3 color1 = mix(BLACK, color, smoothstep(0.0, 10.0, d));
  vec3 color2 = mix(vec3(0.7), color, smoothstep(0.0, -50.0, d));
  return color1 + color2;
}

vec3 ink(vec2 p, vec3 color) {
  if (time > INK_TIME || time == 0.0) {
    return color;
  }
  vec2 startPos = vec2(0.0, HEIGHT * 0.6);
  vec2 endPos = vec2(0.0, -INK_SIZE);
  float t = pow(time / INK_TIME, 2.0);
  vec2 pos = mix(startPos, endPos, t);
  vec2 scale = vec2(mix(1.0, 0.5, t), mix(1.0, 1.5, t));
  float d = sdfCircle((p - pos) / scale, INK_SIZE);
  color = mix(BLACK, color, smoothstep(INK_SIZE, INK_SIZE + 1.0, d));
  return color;
}

vec3 scene(vec2 p, vec3 color) {
  color = mountain(p, color);
  color = tree(p, MAIN_BRANCH_LENGTH, color);
  color = flowerRain(p, color);
  color = ink(p, color);
  return color;
}

void main() {
  vec2 p = toPixel(vUvs);
  vec3 color = background();

  if (p.y > 0.0) {
    color = scene(p - vec2(0.0, 1.0), color);
  } else {
    color = scene(vec2(p.x, -2.0 * remap(sin(p.y / 10.0 + time), -1.0, 1.0,
                                         -GROUND_LEVEL, 0.0)),
                  color);
  }

  gl_FragColor = vec4(color, 1.0);
}
