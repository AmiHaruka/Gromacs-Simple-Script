#!/bin/bash

# 脚本退出时，如果有错误，则立即退出
#set -e

# 核心文件文件目录
CORE_FILES_DIR="a2"
# 动力学参数文件目录
MDP_FILES_DIR="mdp"
# 中间目录
TMP_DIR_303K="tmp-303K-${CORE_FILES_DIR}"
TMP_DIR_373K="tmp-373K-${CORE_FILES_DIR}"
# 分析目录
ANALYSIS_DIR="${CORE_FILES_DIR}/analysis"
# GROMACS命令自定义
GROMACS_CMD="${4:-gmx}" # 如果未提供，则默认使用 'gmx'
Force_DIR="amber14sb_parmbsc1"

# 检查参数是否提供
if [ -z "$CORE_FILES_DIR" ] || [ -z "$MDP_FILES_DIR" ]; then
  echo "Usage: $0 <core_files_dir> <mdp_files_dir> [gromacs_cmd]"
  exit 1
fi

# 创建中间目录和分析目录
mkdir -p "$TMP_DIR_303K"
mkdir -p "$TMP_DIR_373K"
mkdir -p "$ANALYSIS_DIR"

# 核心文件
PDB_FILE="${CORE_FILES_DIR}/ASR2.pdb"
GRO_FILE="${CORE_FILES_DIR}/InitSys.gro"
TOP_FILE="${CORE_FILES_DIR}/topol.top"

# 检查核心文件是否存在
if [ ! -f "$PDB_FILE" ]; then
  echo "Error: Missing required file: $PDB_FILE"
  exit 1
fi

# 函数定义
run_simulation() {
  local TEMP=$1
  local TMP_DIR=$2
  local BOX_GRO_FILE=$3
  local SOL_GRO_FILE=$4
  local NEU_GRO_FILE=$5
  local EM_GRO_FILE=$6
  local EM_CG_GRO_FILE=$7
  local NPT_GRO_FILE=$8
  local Tem=$9
  
  # 1. 生成坐标文件、拓扑文件及定义拓扑文件
  echo "Step 1: Generating coordinate and topology files..."
  $GROMACS_CMD pdb2gmx -f "$PDB_FILE" -o "$GRO_FILE" -p "$TOP_FILE" -ff "$Force_DIR" -water tip3p -ignh
  cp posre.itp "$CORE_FILES_DIR"
  rm posre.itp

  # 2. 指定特定体系（盒子）
  echo "Step 2: Defining the box..."
  $GROMACS_CMD editconf -f "$GRO_FILE" -o "$BOX_GRO_FILE" -box 9. 11. 9. -d 1.0 -c

  # 3. 对盒子执行溶剂化处理
  echo "Step 3: Solvating the box..."
  $GROMACS_CMD solvate -cp "$BOX_GRO_FILE" -cs spc216.gro -p "$TOP_FILE" -o "$SOL_GRO_FILE"

  # 4. 中和体系电荷
  echo "Step 4: Neutralizing the system..."
  $GROMACS_CMD grompp -f "$MDP_FILES_DIR/ions/ions.mdp" -c "$SOL_GRO_FILE" -p "$TOP_FILE" -o "$TMP_DIR/ions.tpr"
  echo "13" | $GROMACS_CMD genion -s "$TMP_DIR/ions.tpr" -o "$NEU_GRO_FILE" -p "$TOP_FILE" -pname NA -nname CL -neutral

  # 5. 能量最小化 - 最速下降法
  echo "Step 5.1: Energy minimization using steepest descent..."
  $GROMACS_CMD grompp -f "$MDP_FILES_DIR/em/em.mdp" -c "$NEU_GRO_FILE" -r "$NEU_GRO_FILE" -p "$TOP_FILE" -o "$TMP_DIR/em.tpr"
  $GROMACS_CMD mdrun -v -deffnm "$TMP_DIR/em" -c "$EM_GRO_FILE"

  # 5. 能量最小化 - 共轭梯度法
  echo "Step 5.2: Energy minimization using conjugate gradient..."
  $GROMACS_CMD grompp -f "$MDP_FILES_DIR/em/em_cg.mdp" -c "$EM_GRO_FILE" -r "$EM_GRO_FILE" -p "$TOP_FILE" -o "$TMP_DIR/em_cg.tpr"
  $GROMACS_CMD mdrun -v -deffnm "$TMP_DIR/em_cg" -c "$EM_CG_GRO_FILE"

  # 6. 简单的NPT弛豫模拟
  echo "Step 6: NPT relaxation simulation..."
  $GROMACS_CMD grompp -f "$MDP_FILES_DIR/npt/npt_$Tem.mdp" -c "$EM_CG_GRO_FILE" -r "$EM_CG_GRO_FILE" -p "$TOP_FILE" -o "$TMP_DIR/npt.tpr"
  $GROMACS_CMD mdrun -v -deffnm "$TMP_DIR/npt" -c "$NPT_GRO_FILE" -dlb yes -pin on -ntmpi 1 -ntomp 6 -nb gpu -bonded gpu  -pme gpu  -update gpu 

  # 7. 提取弛豫后文件，用于分析
  cp "$NPT_GRO_FILE" "$TMP_DIR"
  echo "22" | $GROMACS_CMD energy -f "$TMP_DIR/npt.edr" -o "$ANALYSIS_DIR/${CORE_FILES_DIR}-Vol_${Tem}K.xvg" -dp

  # 8. 保存当前体系下topol文件
  cp "$TOP_FILE" "${TMP_DIR}/topol_${Tem}K.top"

  # 9. RMSD分析
  echo "Performing RMSD analysis..."
  echo -e "4\n4" | $GROMACS_CMD rms -s "$TMP_DIR/npt.tpr" -f "$TMP_DIR/npt.xtc" -o "${ANALYSIS_DIR}/rmsd_${Tem}K.xvg"

  # 10. RMSF分析
  echo "Performing RMSF analysis..."
  echo "4" | $GROMACS_CMD rmsf -s "$TMP_DIR/npt.tpr" -f "$TMP_DIR/npt.xtc" -o "${ANALYSIS_DIR}/rmsf_${Tem}K.xvg" -res

  # 11. DSSP分析
  echo "Performing DSSP analysis..."
  $GROMACS_CMD dssp -s "$TMP_DIR/npt.tpr" -f "$TMP_DIR/npt.xtc" -o "${TMP_DIR}/${Tem}K.dat" -num "${ANALYSIS_DIR}/dssp_${Tem}K.xvg"

  echo "Simulation at $TEMP K completed. Intermediate files are stored in: $TMP_DIR"
}

# 运行303K下的模拟
run_simulation 303 "$TMP_DIR_303K" "$TMP_DIR_303K/box.gro" "$TMP_DIR_303K/sol.gro" "$TMP_DIR_303K/neu.gro" "$TMP_DIR_303K/em.gro" "$TMP_DIR_303K/em_cg.gro" "$TMP_DIR_303K/npt.gro" "303"

# 运行373K下的模拟
run_simulation 373 "$TMP_DIR_373K" "$TMP_DIR_373K/box.gro" "$TMP_DIR_373K/sol.gro" "$TMP_DIR_373K/neu.gro" "$TMP_DIR_373K/em.gro" "$TMP_DIR_373K/em_cg.gro" "$TMP_DIR_373K/npt.gro" "373"

# 移动中间文件夹到核心文件夹下
mv "$TMP_DIR_303K" "$CORE_FILES_DIR"
mv "$TMP_DIR_373K" "$CORE_FILES_DIR"
rm mdout.mdp 

# 完成
echo "Molecular dynamics simulation for both temperatures completed successfully."

