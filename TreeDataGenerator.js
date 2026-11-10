import * as THREE from 'https://cdn.skypack.dev/three@0.136';

const MAX_CPS = 10;
const TRUNK_HEIGHT = 300.0;
const TRUNK_START_WIDTH = 100.0;
const TRUNK_END_WIDTH = 40.0;
const MAIN_BRANCH_LENGTH = 400.0;

const TRUNK_TIME = 1.0;
const BRANCH_TIME = 2.0;
const FLOWER_TIME = 1.0;
const INK_TIME = 3.0;

export class TreeDataGenerator {
    constructor() {
        this.rand = this.createSeededRandom(5);
        this.maxDepth = 3;
        this.treeDatas = [];
        this.createTree();
        this.createBVH(0);
        this.width = 20;
        this.height = this.treeDatas.length;
        const totalSize = this.width * this.height * 4;
        this.dataBuffer = new Float32Array(totalSize);
        this.writeHead = 0;

        for(let i = 0; i < this.height; i++) {
            this.writeTreeData(this.treeDatas[i]);
        }

        this.texture = new THREE.DataTexture(
            this.dataBuffer,
            this.width,
            this.height,
            THREE.RGBAFormat,
            THREE.FloatType
        );
        this.texture.minFilter = THREE.NearestFilter;
        this.texture.magFilter = THREE.NearestFilter;
        this.texture.generateMipmaps = false;
        this.texture.unpackAlignment = 1;
        this.texture.needsUpdate = true;
    }

    writeMatrix(matrix) {
        for(let i = 0; i < 3; i++) {
            for(let j = 0; j < 3; j++ ) {
                this.dataBuffer[this.writeHead + i * 4 +j] = matrix.elements[i * 3 + j];
            }
        }
        this.writeHead += 12;
    }

    writeVector2(vec) {
        this.dataBuffer[this.writeHead] = vec.x
        this.dataBuffer[this.writeHead + 1] = vec.y
        this.writeHead += 2
    }

    writeVector3(vec) {
        this.dataBuffer[this.writeHead] = vec.x
        this.dataBuffer[this.writeHead + 1] = vec.y
        this.dataBuffer[this.writeHead + 2] = vec.z
        this.writeHead += 3
    }

    writeValue(v) {
        this.dataBuffer[this.writeHead] = v;
        this.writeHead += 1;
    }

    writeArray(array, num) {
        for(let i = 0; i < Math.min(num, array.length); i++) {
            this.dataBuffer[this.writeHead + i] = array[i];
        }
        this.writeHead += num;
    }

    writeTreeData(treeData) {
        // 1 - 6
        this.writeMatrix(treeData.worldToLocal);
        this.writeMatrix(treeData.localToParent);
        
        // 6 - 7
        this.writeVector3(treeData.startColor);
        this.writeValue(treeData.startWidth);

        // 7 - 8
        this.writeVector3(treeData.endColor);
        this.writeValue(treeData.endWidth);

        // 8 - 9
        this.writeValue(treeData.startTime);
        this.writeValue(treeData.endTime);
        this.writeValue(treeData.controlPointsNum);
        this.writeValue(treeData.childNum);

        // 9 - 14
        for(let i = 0; i < MAX_CPS; i++) {
            this.writeVector2(treeData.controlPoints[i]);
        }
        
        // 14 - 15
        this.writeArray(treeData.boundingBox, 4);

        // 15 - 16
        this.writeArray(treeData.bvh, 4);

        // 16 - 18
        this.writeArray(treeData.childIdx, 8);

        // 18 - 20
        this.writeValue(treeData.flowerNum);
        this.writeArray(treeData.flowerIdx, 7);
    }

    boxIncludePoint(box, pos) {
        box[0] = Math.min(box[0], pos.x);
        box[1] = Math.max(box[1], pos.x);
        box[2] = Math.min(box[2], pos.y);
        box[3] = Math.max(box[3], pos.y);
    }

    boxIncludeBox(box, other) {
        box[0] = Math.min(box[0], other[0]);
        box[1] = Math.max(box[1], other[1]);
        box[2] = Math.min(box[2], other[2]);
        box[3] = Math.max(box[3], other[3]);
    }

    createBoundingBoxForTreeData(treeData) {
        for(let i = 0; i < treeData.controlPointsNum; i++) {
            const leftBottom = new THREE.Vector2();
            leftBottom.copy(treeData.controlPoints[i]);
            const offset = this.mix(treeData.startWidth, treeData.endWidth, i / (treeData.controlPointsNum - 1.0));
            leftBottom.subScalar(offset);
            this.boxIncludePoint(treeData.boundingBox, leftBottom);
            const rightTop = new THREE.Vector2();
            rightTop.copy(treeData.controlPoints[i]);
            rightTop.addScalar(offset);
            this.boxIncludePoint(treeData.boundingBox, rightTop);
        }
    }

    transformBox(box, transform) {
        const newBox = [1e6, -1e6, 1e6, -1e6];
        const v1 = new THREE.Vector2(box[0], box[2]);
        v1.applyMatrix3(transform);
        const v2 = new THREE.Vector2(box[1], box[2]);
        v2.applyMatrix3(transform);
        const v3 = new THREE.Vector2(box[0], box[3]);
        v3.applyMatrix3(transform);
        const v4 = new THREE.Vector2(box[1], box[3]);
        v4.applyMatrix3(transform);
        this.boxIncludePoint(newBox, v1);
        this.boxIncludePoint(newBox, v2);
        this.boxIncludePoint(newBox, v3);
        this.boxIncludePoint(newBox, v4);
        return newBox;
    }

    createBVH(idx) {
        this.boxIncludeBox(this.treeDatas[idx].bvh, this.treeDatas[idx].boundingBox);

        if(this.treeDatas[idx].childNum == 0) {
            return;
        }

        for(let i = 0; i < this.treeDatas[idx].childNum; i++) {
            const j = this.treeDatas[idx].childIdx[i];
            this.createBVH(j);
            this.boxIncludeBox(this.treeDatas[idx].bvh, this.transformBox(this.treeDatas[j].bvh, this.treeDatas[j].localToParent));
        }
    }

    mix(value1, value2, t) {
        return value1 * (1.0 - t) + value2 * t;
    }

    mixVectors2(v1, v2, t) {
        const vp1 = new THREE.Vector2();
        vp1.copy(v1);
        vp1.multiplyScalar(1.0 - t);

        const vp2 = new THREE.Vector2();
        vp2.copy(v2);
        vp2.multiplyScalar(t);

        const v = new THREE.Vector2();
        v.addVectors(vp1, vp2);
        return v;
    }

    mixVectors3(v1, v2, t) {
        const vp1 = new THREE.Vector3();
        vp1.copy(v1);
        vp1.multiplyScalar(1.0 - t);

        const vp2 = new THREE.Vector3();
        vp2.copy(v2);
        vp2.multiplyScalar(t);

        const v = new THREE.Vector3();
        v.addVectors(vp1, vp2);
        return v;
    }

    step(edge, x) {
        if (x < edge) {
            return 0.0;
        }
        return 1.0;
    }

    proj(p, p1, p2) {
        const v = new THREE.Vector2();
        const v2 = new THREE.Vector2();
        v.subVectors(p, p1);
        v2.subVectors(p2, p1);
        const v2Len = v2.length();
        const projLen = v.dot(v2) / v2Len;
        const projV = new THREE.Vector2(v2.x * projLen/ v2Len, v2.y * projLen/ v2Len);
        projV.add(p1);
        return projV;
    }

    bezier(cp1, cp2, cp3, t) {
        const p1 = new THREE.Vector2();
        p1.copy(cp1);
        p1.multiplyScalar((1 - t) * (1 - t));

        const p2 = new THREE.Vector2();
        p2.copy(cp2);
        p2.multiplyScalar(2.0 * t * (1 - t));

        const p3 = new THREE.Vector2();
        p3.copy(cp3);
        p3.multiplyScalar(t * t);

        const v = new THREE.Vector2();
        v.addVectors(p1, p2);
        v.add(p3);
        return v;
    }

    curve(controlPoints, controlPointsNum, t) {
        if (controlPointsNum == 1) {
            return controlPoints[0];
        }

        if (controlPointsNum == 2) {
            return this.mixVectors2(controlPointsNum[0], controlPointsNum[1], t);
        }

        const curveNum = (controlPointsNum - 1.0) * 0.5;
        const tm = t * curveNum;
        const ti = Math.floor(tm);
        const idx = 2 * ti;
        if(idx >= controlPointsNum - 1) {
            return controlPoints[controlPointsNum - 1];
        }
        const tf = tm - ti;
        return this.bezier(controlPoints[idx], controlPoints[idx + 1], controlPoints[idx + 2], tf);
    }

    makeRotate(angle) {
        const c = Math.cos(angle);
        const s = Math.sin(angle);
        const mat = new THREE.Matrix3().set(c, -s, 0.0, s, c, 0.0, 0.0, 0.0, 1.0);
        return mat;
    }

    makeTranslate(tx, ty) {
        return new THREE.Matrix3().set(1.0, 0.0, tx, 0.0, 1.0, ty, 0.0, 0.0, 1.0);
    }

    makeScale(sx, sy) {
        return new THREE.Matrix3().set(sx, 0.0, 0.0, 0.0, sy, 0.0, 0.0, 0.0, 1.0);
    }

    createTrunk() {
        const trunk = new TreeData();
        trunk.startWidth = TRUNK_START_WIDTH;
        trunk.endWidth = TRUNK_END_WIDTH;
        trunk.startTime = INK_TIME;
        trunk.endTime = INK_TIME + TRUNK_TIME;
        trunk.controlPointsNum = 3;
        trunk.controlPoints[0].set(0.0, 0.0);
        trunk.controlPoints[1].set(-0.1 * TRUNK_HEIGHT, TRUNK_HEIGHT * 0.5);
        trunk.controlPoints[2].set(0.0, TRUNK_HEIGHT);
        this.createBoundingBoxForTreeData(trunk);
        trunk.depth = 0;
        return trunk;
    }

    createFlower(parentData, t) {
        const flowerData = new TreeData();
        const ori = this.curve(parentData.controlPoints, parentData.controlPointsNum, t);
        const angle = Math.PI * this.rand();
        const scale = this.mix(2.0, 7.0, this.rand());
        flowerData.worldToLocal.multiplyMatrices(this.makeTranslate(-ori.x, -ori.y), parentData.worldToLocal);
        flowerData.worldToLocal.premultiply(this.makeRotate(-angle));
        flowerData.worldToLocal.premultiply(this.makeScale(1.0/scale, 1.0/scale));
        flowerData.localToParent.multiplyMatrices(this.makeTranslate(ori.x, ori.y), this.makeRotate(angle));
        flowerData.localToParent.multiply(this.makeScale(scale, scale));

        flowerData.startTime = parentData.startTime + BRANCH_TIME * t;
        flowerData.endTime = flowerData.startTime + FLOWER_TIME;
        flowerData.depth = this.maxDepth;
        flowerData.boundingBox = [-4.0, 4.0, -4.0, 4.0];
        this.treeDatas.push(flowerData);
        parentData.flowerIdx.push(this.treeDatas.length - 1);
    }

    createBranch(parentData, t, angle, len, startWidth) {
        const branchData = new TreeData();
        const ori = this.curve(parentData.controlPoints, parentData.controlPointsNum, t);

        branchData.worldToLocal.multiplyMatrices(this.makeTranslate(-ori.x, -ori.y), parentData.worldToLocal);
        branchData.worldToLocal.premultiply(this.makeRotate(-angle));
        branchData.localToParent.multiplyMatrices(this.makeTranslate(ori.x, ori.y), this.makeRotate(angle));

        branchData.controlPoints[0] = new THREE.Vector2(0.0);
        branchData.controlPoints[1] = new THREE.Vector2(0.0, this.mix(0.1, 0.5, this.rand()) * len);
        branchData.controlPoints[2] = new THREE.Vector2(-1.0 * this.mix(0.1, 0.25, this.rand()) * Math.sign(angle) * len,
                                      this.mix(0.5, 0.6, this.rand()) * len);
        branchData.controlPoints[4] = new THREE.Vector2(this.mix(0.0, 0.1, -1.0 * this.rand()) * Math.sign(angle) * len, len);
        branchData.controlPoints[3] = this.proj(branchData.controlPoints[4], branchData.controlPoints[1], branchData.controlPoints[2]);
        branchData.controlPointsNum = 5;

        branchData.startWidth = startWidth;
        branchData.endWidth = branchData.startWidth * 0.2;
      
        branchData.startColor = this.mixVectors3(parentData.startColor, parentData.endColor, t);
        branchData.endColor = new THREE.Vector3(0.4, 0.4, 0.4);
        branchData.startTime = this.mix(parentData.startTime, parentData.endTime, t);
        branchData.endTime = branchData.startTime + BRANCH_TIME;
        branchData.depth = parentData.depth + 1;
        this.createBoundingBoxForTreeData(branchData);

        this.treeDatas.push(branchData);
        parentData.childIdx.push(this.treeDatas.length - 1);

        if(branchData.depth < this.maxDepth) {
            branchData.childNum = Math.floor(this.mix(1, 5, this.rand()));
            for(let i = 0; i< branchData.childNum; i++) {
                const childT = this.mix(0.3, 0.8, this.rand());
                const childAngle =
                    this.mix(Math.PI / 4.0, Math.PI / 3.0, this.rand()) * (2.0 * this.step(0.5, this.rand()) - 1.0);
                const childLen = this.mix(0.8, 0.2, childT) * len;
                const childWidth = this.mix(branchData.startWidth, branchData.endWidth, childT);
                this.createBranch(branchData, childT, childAngle, childLen, childWidth);
            }
        }

        branchData.flowerNum = Math.floor(this.mix(5, 7, this.rand()));
        for(let i = 0; i< branchData.flowerNum; i++) {
            const flowerT = this.mix(0.3, 1.0, this.rand());
            this.createFlower(branchData, flowerT);
        }
        return branchData;
    }

    createTree() {
        const trunk = this.createTrunk();
        trunk.childNum = 5;
        this.treeDatas.push(trunk);
        for (let i = 0; i < 5; i++) {
            const angle = this.mix(-Math.PI / 3.0, Math.PI / 3.0, (i + this.rand()) / 5.0);
            const t = 1.0;
            const len = MAIN_BRANCH_LENGTH;
            const startWidth = TRUNK_END_WIDTH * 0.5;
            this.createBranch(trunk, t, angle, len, startWidth);
        }
    }

    createSeededRandom(initialSeed) {
        let state = initialSeed;
    
        // This is the function you will call to get numbers
        return function() {
            let t = state += 0x6D2B79F5;
            t = Math.imul(t ^ (t >>> 15), t | 1);
            t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
            return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
        };
    }
}

/* Generate the branch data as follow:
- worldToLocal (3)
- localToParent (3)
- startColor, startWidth (1)
- endColor, endWidth, (1) 
- startTime, endTime, controlPointsNum, childNum (1)
- controlPoints[MAX_CPS] (MAX_CPS / 2 aka. 5)
- boundingBox (1)
- bvh (1)
- childIdx (2)
*/

class TreeData {
    constructor() {
        this.worldToLocal = new THREE.Matrix3();
        this.localToParent = new THREE.Matrix3();
        this.startWidth = 0.0;
        this.endWidth = 0.0;
        this.startColor = new THREE.Vector3();
        this.endColor = new THREE.Vector3();
        this.startTime = 0.0;
        this.endTime = 0.0;
        this.controlPointsNum = 0;
        this.childNum = 0;
        this.controlPoints = Array.from({ length: 10 }, () => new THREE.Vector2(0.0, 0.0));
        this.boundingBox = [1e6, -1e6, 1e6, -1e6];
        this.bvh= [1e6, -1e6, 1e6, -1e6];
        this.childIdx = [];
        this.flowerNum = 0;
        this.flowerIdx = [];
        this.depth = 0;
    }
}

