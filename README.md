# Gromacs-Simple-Script

**实验室偶遇多流程任务，步骤繁琐黏如怪物，拼劲全力也无法战胜**

此脚本是能够在 ```Ubuntu22.04 LTS```系统上自动化运行GROMACS分子动力学模拟脚本，按照指定步骤完成从坐标文件生成到NPT弛豫模拟的全过程。

## 使用说明

### 脚本参数

- `CORE_FILES_DIR`: 核心文件文件夹（如`example.pdb,topol.top`等文件）。
- `MDP_FILES_DIR`: 动力学参数文件目录。
- `TMP_DIR`: 用于存放模拟过程中产生的中间文件的目录。
- `GROMACS_CMD`: 可选参数，自定义GROMACS命令，默认使用`gmx`。

### 运行脚本

1. **保存脚本**：将脚本保存为`run_gromacs_simulation.sh`。
2. **赋予执行权限**：
   ```bash
   chmod +x run_gromacs_simulation.sh
   ```
3. **执行脚本** :
   ```bash
   bash run_gmx.sh
   ```

# 备注
请确保已安装GROMACS，并能从命令行调用。
确保提供的文件路径和目录存在。
该脚本默认假定参数文件和核心文件已准备好，如有需要请根据实际情况进行调整。

