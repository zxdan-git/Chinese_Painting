### Before Optimization

Build tree structure in fragment shader, check each fragment with all branches sdf.

![demo (before optmization)](./pics/demo.gif)

### After Optimization

Build tree outside the shader and save the tree structure in a data texture. Build up bounding box hierarchy to check the fragments in the bounding box.

![demo (after optimization)](./pics/demo2.gif)

#### Data texture
![data texture](./pics/data_texture.png)

#### Bounding boxes

![bounding box](./pics/bounding_box.png)

#### Bounding box hierarchy
| level 1 | level 2| level 3|
| --------- | --------- | --------- |
|![level 1](./pics/bvh1.png) | ![level 2](./pics/bvh2.png)| ![level 3](./pics/bvh3.png)
