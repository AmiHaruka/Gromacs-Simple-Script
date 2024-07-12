# Gromacs-Simple-Script

##执行前请优先阅读脚本

> 注意，脚本的第**13-16**，**43**，**56**，**107**，**127**行可能不适配于所有体系，仅供参考

**实验室偶遇多流程任务，步骤繁琐强如怪物，拼劲全力也无法战胜**

此脚本能够在 `Linux` 系统上自动化运行三次不同温度下的 GROMACS 分子动力学模拟，按照指定步骤完成从坐标文件生成到 MD 模拟的全过程，并执行后续的 RMSD、RMSF等分析;



>  --主要流程已用函数描述，可以随意自行修改有关参数
   --倘若打算再超算上运行，`Force_DIR` 参数可能不会起到作用，一个最简单的解决办法是为每一个核心文件夹添加力场文件

## 使用说明

### 脚本参数

- `CORE_FILES_DIR`: 核心文件文件目录（如 `example.pdb`, `topol.top`（后续自主生成） 等文件）。
- `MDP_FILES_DIR`: 动力学参数文件目录。
- `GROMACS_CMD`: 自定义 GROMACS 命令，默认使用 `gmx`。
- `Force_DIR` : 力场文件目录，需要至于 sh 脚本所在目录 `.`
- 更多请阅读相关脚本

### 运行脚本

1. **保存脚本**：将脚本保存为 `run_gromacs_simulation.sh`,调整有关参数。
2. **赋予执行权限**：
   ```bash
   chmod +x run_gromacs_simulation.sh
   ```
3. **执行脚本**：
   ```bash
   bash ./run_gromacs_simulation.sh 
   ```

### 示例目录结构

假设核心文件目录为 `你的目录`，MDP 文件目录为 `MDP`，脚本的执行会生成以下目录结构：
可自行去脚本的14至16行修改核型文件目录等

```
你的目录/
├── 你的结构.pdb
├── InitSys.gro
├── topol.top
├── posre.itp
├── analysis/
│   ├── a2-Vol_303K.xvg
│   ├── a2-Vol_373K.xvg
│   ├── rmsd_303K.xvg
│   ├── rmsd_373K.xvg
│   ├── rmsf_303K.xvg
│   ├── rmsf_373K.xvg
│   ├── dssp_303K.xvg
│   └── dssp_373K.xvg
├── Tmp-你的目录
│   ├── tmp-303K-a2
│   └── ...
```

## 步骤

### 动力学文件生成

1. 生成坐标文件和拓扑文件。
2. 指定体系的盒子大小。
3. 对盒子进行溶剂化处理。
4. 中和体系电荷。
5. 使用最速下降法进行能量最小化。
6. 使用共轭梯度法进行能量最小化。
7. 进行简单的 NPT 弛豫模拟。
8. 不同温度下的MD模拟
8. 提取模拟后的文件用于分析。

### 分析

1. RMSD 分析
2. RMSF 分析
3. DSSP 分析(DSSP.dat文件将会置于{TMP_DIR}处)

所有分析结果都会存储在 `analysis` 目录中，便于后续的处理和分析。

## 关键步骤

1. **生成坐标文件和拓扑文件**：
    ```bash
    $GROMACS_CMD pdb2gmx -f "$PDB_FILE" -o "$GRO_FILE" -p "$TOP_FILE" -ff "$Force_DIR" -water tip3p -ignh
    ```
2. **指定体系的盒子大小**：
    ```bash
    $GROMACS_CMD editconf -f "$GRO_FILE" -o "$BOX_GRO_FILE" -box 9. 11. 9. -d 1.0 -c
    ```
3. **对盒子进行溶剂化处理**：
    ```bash
    $GROMACS_CMD solvate -cp "$BOX_GRO_FILE" -cs spc216.gro -p "$TOP_FILE" -o "$SOL_GRO_FILE"
    ```
4. **中和体系电荷**：
    ```bash
    $GROMACS_CMD grompp -f "$MDP_FILES_DIR/ions/ions.mdp" -c "$SOL_GRO_FILE" -p "$TOP_FILE" -o "$TMP_DIR/ions.tpr"
    echo "13" | $GROMACS_CMD genion -s "$TMP_DIR/ions.tpr" -o "$NEU_GRO_FILE" -p "$TOP_FILE" -pname NA -nname CL -neutral
    ```
5. **能量最小化**：
    ```bash
    $GROMACS_CMD grompp -f "$MDP_FILES_DIR/em/em.mdp" -c "$NEU_GRO_FILE" -r "$NEU_GRO_FILE" -p "$TOP_FILE" -o "$TMP_DIR/em.tpr"
    $GROMACS_CMD mdrun -v -deffnm "$TMP_DIR/em" -c "$EM_GRO_FILE"

    $GROMACS_CMD grompp -f "$MDP_FILES_DIR/em/em_cg.mdp" -c "$EM_GRO_FILE" -r "$EM_GRO_FILE" -p "$TOP_FILE" -o "$TMP_DIR/em_cg.tpr"
    $GROMACS_CMD mdrun -v -deffnm "$TMP_DIR/em_cg" -c "$EM_CG_GRO_FILE"
    ```
6. **NPT 弛豫模拟**：
    ```bash
    $GROMACS_CMD grompp -f "$MDP_FILES_DIR/npt/npt_$Temp.mdp" -c "$EM_CG_GRO_FILE" -r "$EM_CG_GRO_FILE" -p "$TOP_FILE" -o "$TMP_DIR/npt.tpr"
    $GROMACS_CMD mdrun -v -deffnm "$TMP_DIR/npt" -c "$NPT_GRO_FILE"
    ```
7. **保存当前体系下的拓扑文件**：
    ```bash
    mv "$TOP_FILE" "${TMP_DIR}/${Temp}K-${CORE_FILES_DIR}"
    ```
8. **RMSD 分析**：
    ```bash
    $GROMACS_CMD rms -s "$TMP_DIR/npt.tpr" -f "$TMP_DIR/npt.xtc" -o "${ANALYSIS_DIR}/rmsd_${Temp}K.xvg"
    ```
9. **RMSF 分析**：
    ```bash
    $GROMACS_CMD rmsf -s "$TMP_DIR/npt.tpr" -f "$TMP_DIR/npt.xtc" -o "${ANALYSIS_DIR}/rmsf_${Temp}K.xvg" -res
    ```
10. **DSSP 分析**：
    ```bash
    $GROMACS_CMD dssp -s "$TMP_DIR/npt.tpr" -f "$TMP_DIR/npt.xtc" -o "${TMP_DIR}/${Temp}K.dat" -num "${ANALYSIS_DIR}/dssp_${Temp}K.xvg"
    ```

## 备注

请确保已安装 GROMACS，并能从命令行调用。  
确保提供的文件路径和目录存在。  
**该脚本默认假定参数文件和核心文件已准备好，如有需要请根据实际情况进行调整。**
