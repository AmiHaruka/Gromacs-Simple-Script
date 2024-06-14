#!/bin/bash

# 脚本退出时，如果有错误，则立即退出（已注释）
#set -e

# 核心文件目录
CORE_FILES_DIR="YOUTDIR"
# 动力学参数文件目录
MDP_FILES_DIR="mdp"
# 中间目录
TMP_DIR="tmp-${CORE_FILES_DIR}"
# 自定义调用的GROMACS程序
GROMACS_CMD="${4:-gmx}" # 如果未提供，则默认使用 'gmx'

# 检查参数是否提供
if [ -z "$CORE_FILES_DIR" ] || [ -z "$MDP_FILES_DIR" ] || [ -z "$TMP_DIR" ]; then
  echo "Usage: $0 <core_files_dir> <mdp_files_dir> <tmp_dir> [gromacs_cmd]"
  exit 1
fi

# 创建中间目录
mkdir -p "$TMP_DIR"

# 核心文件
PDB_FILE="${CORE_FILES_DIR}/YOUR.pdb"
GRO_FILE="${CORE_FILES_DIR}/example.gro"
TOP_FILE="${CORE_FILES_DIR}/topol.top"
#ITP_FILE="${CORE_FILES_DIR}/posre.itp"
BOX_GRO_FILE="${TMP_DIR}/box.gro"
SOL_GRO_FILE="${TMP_DIR}/sol.gro"
NEU_GRO_FILE="${TMP_DIR}/neu.gro"
EM_GRO_FILE="${TMP_DIR}/em.gro"
EM_CG_GRO_FILE="${TMP_DIR}/em_cg.gro"
NPT_GRO_FILE="${CORE_FILES_DIR}/npt.gro"

# 检查核心文件是否存在
if [ ! -f "$PDB_FILE" ]; then
  echo "Error: Missing required file: $PDB_FILE"
  exit 1
fi

# 1. 生成坐标文件、拓扑文件及定义拓扑文件
echo "Step 1: Generating coordinate and topology files..."
$GROMACS_CMD pdb2gmx -f "$PDB_FILE" -o "$GRO_FILE" -p "$TOP_FILE"  -ignh
$2
$1

cp posre.itp "$CORE_FILES_DIR"
rm posre.itp

# 2. 指定特定体系（盒子）
echo "Step 2: Defining the box..."
$GROMACS_CMD editconf -f "$GRO_FILE" -o "$BOX_GRO_FILE" -bt cubic -d 1.0 -c

# 3. 对盒子执行溶剂化处理
echo "Step 3: Solvating the box..."
$GROMACS_CMD solvate -cp "$BOX_GRO_FILE" -cs spc216.gro -p "$TOP_FILE" -o "$SOL_GRO_FILE"

# 4. 中和体系电荷
echo "Step 4: Neutralizing the system..."
$GROMACS_CMD grompp -f "$MDP_FILES_DIR/ions/ions.mdp" -c "$SOL_GRO_FILE" -p "$TOP_FILE" -o "$TMP_DIR/ions.tpr"
$GROMACS_CMD genion -s "$TMP_DIR/ions.tpr" -o "$NEU_GRO_FILE"  -p "$TOP_FILE" -pname NA -nname CL -neutral
$13

# 5. 能量最小化 - 最速下降法
echo "Step 5.1: Energy minimization using steepest descent..."
$GROMACS_CMD grompp -f "$MDP_FILES_DIR/em/em.mdp" -c "$NEU_GRO_FILE" -r "$NEU_GRO_FILE" -p "$TOP_FILE"   -o "$TMP_DIR/em.tpr"
$GROMACS_CMD mdrun -v -deffnm "$TMP_DIR/em" -c "$EM_GRO_FILE"

# 5. 能量最小化 - 共轭梯度法
echo "Step 5.2: Energy minimization using conjugate gradient..."
$GROMACS_CMD grompp -f "$MDP_FILES_DIR/em/em_cg.mdp" -c "$EM_GRO_FILE" -r "$EM_GRO_FILE" -p "$TOP_FILE" -o "$TMP_DIR/em_cg.tpr"
$GROMACS_CMD mdrun -v -deffnm "$TMP_DIR/em_cg" -c "$EM_CG_GRO_FILE"

# 6. 简单的NPT弛豫模拟
echo "Step 6: NPT relaxation simulation..."
$GROMACS_CMD grompp -f "$MDP_FILES_DIR/npt/npt.mdp" -c "$EM_CG_GRO_FILE" -r "$EM_CG_GRO_FILE" -p "$TOP_FILE" -o "$TMP_DIR/npt.tpr"
$GROMACS_CMD mdrun -v -deffnm "$TMP_DIR/npt" -c "$NPT_GRO_FILE"

# 7. 提取弛豫后文件，用于分析
cp "$CORE_FILES_DIR/npt.gro" "$TEP_DIR"
$GROMACS_CMD energy  -f "$TMP_DIR/npt.edr" -o "$TMP_DIR"/"$CORE_FILES_DIR"-Vol.xvg -dp

mv "$TMP_DIR" "$CORE_FILES_DIR"
rm mdout.mdp 

# 完成
echo "Molecular dynamics simulation completed successfully."
echo "Intermediate files are stored in: $TMP_DIR"

