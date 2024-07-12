#!/bin/bash

echo "************************************************************************"
echo "********************************并非脚本********************************"
echo "******实验室偶遇多流程任务，步骤繁琐强如怪物，拼劲全力也无法战胜*******"
echo "************************AmiHaruka=SAN***********************************"
echo "************************************************************************"
echo " "
echo " "
echo " "

###
###
CORE_FILES_DIR="a1"
PDB_FILE="${CORE_FILES_DIR}/ASR1.pdb"
MDP_FILES_DIR="MDP"
###
###

TMP_DIR="Tmp-${CORE_FILES_DIR}"
ANALYSIS_DIR="${CORE_FILES_DIR}/analysis"
GROMACS_CMD="${4:-gmx}"
Force_DIR="amber14sb_parmbsc1"
GRO_FILE="${CORE_FILES_DIR}/InitSys.gro"
TOP_FILE="${CORE_FILES_DIR}/topol.top"

mkdir -p "$TMP_DIR"
mkdir -p "$ANALYSIS_DIR"

prepare_system() {

    echo "********************************************************************"
    echo "******* Step 1: Generating coordinate and topology files... *******" 
    echo "*******************************************************************"
    
    $GROMACS_CMD pdb2gmx -f "$PDB_FILE" -o "$GRO_FILE" -p "$TOP_FILE" -ff "$Force_DIR" -water tip3p -ignh
    mv posre.itp "$CORE_FILES_DIR"

    echo "*******************************************"
    echo "******* Step 2: Defining the box... *******"
    echo "*******************************************" 
    
    $GROMACS_CMD editconf -f "$GRO_FILE" -o "$TMP_DIR/box.gro" -box 9. 11. 9. -d 1.0 -c

    echo "*******************************************************************"
    echo "****************Step 3: Solvating the box...***********************"
    echo "*******************************************************************"
    
    $GROMACS_CMD solvate -cp "$TMP_DIR/box.gro" -cs spc216.gro -p "$TOP_FILE" -o "$TMP_DIR/sol.gro"

    echo "**************************************************"
    echo "******* Step 4: Neutralizing the system... *******" 
    echo "**************************************************"
    
    $GROMACS_CMD grompp -f "$MDP_FILES_DIR/ions/ions.mdp" -c "$TMP_DIR/sol.gro" -p "$TOP_FILE" -o "$TMP_DIR/ions.tpr"
    echo "13" | $GROMACS_CMD genion -s "$TMP_DIR/ions.tpr" -o "$TMP_DIR/neu.gro" -p "$TOP_FILE" -pname NA -nname CL -neutral

    echo "***********************************************************************"
    echo "******* Step 5.1: Energy minimization using steepest descent... *******"
    echo "***********************************************************************"
    
    $GROMACS_CMD grompp -f "$MDP_FILES_DIR/em/em.mdp" -c "$TMP_DIR/neu.gro" -r "$TMP_DIR/neu.gro" -p "$TOP_FILE" -o "$TMP_DIR/em.tpr"
    $GROMACS_CMD mdrun -v -deffnm "$TMP_DIR/em" -c "$TMP_DIR/em.gro"

    echo "*************************************************************************"
    echo "******* Step 5.2: Energy minimization using conjugate gradient... *******" 
    echo "*************************************************************************"
    
    $GROMACS_CMD grompp -f "$MDP_FILES_DIR/em/em_cg.mdp" -c "$TMP_DIR/em.gro" -r "$TMP_DIR/em.gro" -p "$TOP_FILE" -o "$TMP_DIR/em_cg.tpr"
    $GROMACS_CMD mdrun -v -deffnm "$TMP_DIR/em_cg" -c "$TMP_DIR/em_cg.gro"

    echo "****************************************************"
    echo "******* Step 6: NPT relaxation simulation... *******"
    echo "****************************************************"
    
    $GROMACS_CMD grompp -f "$MDP_FILES_DIR/npt/npt.mdp" -c "$TMP_DIR/em_cg.gro" -r "$TMP_DIR/em_cg.gro" -p "$TOP_FILE" -o "$TMP_DIR/npt.tpr"
    $GROMACS_CMD mdrun -v -deffnm "$TMP_DIR/npt" -c "$TMP_DIR/npt.gro" 

    cp "$TMP_DIR/npt.gro" "${CORE_FILES_DIR}/npt_ready.gro"

}


run_md_simulation() {
    local TEMP=$1
    local MDP_FILE="md/md_${TEMP}C.mdp"
    local OUTPUT_PREFIX="$TMP_DIR/md_${TEMP}C"

    echo "**************************************************"
    echo "******* Running MD simulation at ${TEMP}C *******"
    echo "**************************************************"
    
    $GROMACS_CMD grompp -f "$MDP_FILES_DIR/$MDP_FILE" -c "${CORE_FILES_DIR}/npt_ready.gro" -p "$TOP_FILE" -o "${OUTPUT_PREFIX}.tpr"
    $GROMACS_CMD mdrun -v -deffnm "${OUTPUT_PREFIX}" 

}


analyze_simulation() {
    mkdir -p "$ANALYSIS_DIR"
    cp "$TOP_FILE" "$ANALYSIS_DIR/topol.top"

    echo "**************************************************"
    echo "*************Starting analysis********************"
    echo "**************************************************"
    
    for TEMP in 37 60 80; do
        local OUTPUT_PREFIX="$TMP_DIR/md_${TEMP}C"

        $GROMACS_CMD trjconv -s "${OUTPUT_PREFIX}.tpr"   -f "${OUTPUT_PREFIX}.xtc" -center -pbc mol -o "${OUTPUT_PREFIX}_new.xtc" <<< "1 0"
        rm "${OUTPUT_PREFIX}.xtc"
        $GROMACS_CMD trjconv -s "${OUTPUT_PREFIX}.tpr" -f "${OUTPUT_PREFIX}_new.xtc" -fit rot+trans -o  "${OUTPUT_PREFIX}_fit.xtc"  <<< "1 0" 

        $GROMACS_CMD rms -s "${OUTPUT_PREFIX}.tpr" -f "${OUTPUT_PREFIX}_fit.xtc" -o "${ANALYSIS_DIR}/rmsd_${TEMP}C.xvg" -b 20000 <<< "4 4"
        $GROMACS_CMD rms -s "${OUTPUT_PREFIX}.tpr" -f "${OUTPUT_PREFIX}_fit.xtc" -o "${ANALYSIS_DIR}/rmsd_${TEMP}C_100ns.xvg"  <<< "4 4"
        $GROMACS_CMD rmsf -s "${OUTPUT_PREFIX}.tpr" -f "${OUTPUT_PREFIX}_fit.xtc" -o "${ANALYSIS_DIR}/rmsf_${TEMP}C.xvg" -res -b 20000 -oq "${ANALYSIS_DIR}/${TEMP}C_bfac.pdb" <<< "4"
        $GROMACS_CMD dssp -s "${OUTPUT_PREFIX}.tpr" -f "${OUTPUT_PREFIX}_fit.xtc" -o "${TMP_DIR}/${TEMP}K.dat" -num "${ANALYSIS_DIR}/dssp_${TEMP}C.xvg" -b 20000

        cp "$TOP_FILE" "$ANALYSIS_DIR/topol_${TEMP}C.top"
    done
    
}


prepare_system

for TEMP in 37 60 80; do
    run_md_simulation ${TEMP}
done 

analyze_simulation

mv "${TMP_DIR}" "${CORE_FILES_DIR}"

echo "**************************************************"
echo "***************** Task done **********************"
echo "**************************************************"
