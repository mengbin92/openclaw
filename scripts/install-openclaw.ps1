# OpenClaw 一键部署脚本 (PowerShell)
# 支持: Windows 10/11
# 使用方法: 以管理员身份运行 PowerShell, 然后执行: .\install-openclaw.ps1

param(
    [string]$ApiKey = "",
    [int]$ModelChoice = 2,
    [string]$BaseUrl = ""
)

# 检查执行策略
$executionPolicy = Get-ExecutionPolicy
if ($executionPolicy -eq "Restricted" -or $executionPolicy -eq "AllSigned") {
    Write-Host "============================================" -ForegroundColor Red
    Write-Host "           执行策略受限" -ForegroundColor Red
    Write-Host "============================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "当前 PowerShell 执行策略为: $executionPolicy" -ForegroundColor Yellow
    Write-Host "这会导致无法运行脚本。" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "请使用以下命令运行脚本:" -ForegroundColor Green
    Write-Host ""
    Write-Host "    powershell -ExecutionPolicy Bypass -File .\install-openclaw.ps1" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "如果需要传递 API Key:" -ForegroundColor Green
    Write-Host ""
    Write-Host "    powershell -ExecutionPolicy Bypass -File .\install-openclaw.ps1 -ApiKey \"你的API密钥\"" -ForegroundColor Cyan
    Write-Host ""
    exit 1
}

# 颜色函数
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    $colors = @{
        "Red" = [ConsoleColor]::Red
        "Green" = [ConsoleColor]::Green
        "Yellow" = [ConsoleColor]::Yellow
        "Blue" = [ConsoleColor]::Blue
        "White" = [ConsoleColor]::White
    }
    Write-Host $Message -ForegroundColor $colors[$Color]
}

# 变量
$OpenclawDir = "$env:USERPROFILE\.openclaw"
$ConfigFile = "$OpenclawDir\openclaw.json"
$NpmRegistry = "https://registry.npmmirror.com/"

# 主函数
function Main {
    # 欢迎信息
    Write-ColorOutput "============================================" "Blue"
    Write-ColorOutput "         OpenClaw 一键部署脚本 (Windows)" "Blue"
    Write-ColorOutput "============================================" "Blue"
    Write-Host ""

    # 检测操作系统
    Write-ColorOutput "[INFO] 检测操作系统..." "Blue"
    $os = $env:OS
    Write-ColorOutput "[INFO] 操作系统: Windows" "Green"

    # 检查 Node.js 和 Git
    Write-Host ""
    Write-ColorOutput ">>> 步骤 1/4: 检查 Node.js 和 Git" "Blue"

    try {
        $nodeVersion = node --version 2>$null
        if ($nodeVersion) {
            Write-ColorOutput "[SUCCESS] Node.js 已安装: $nodeVersion" "Green"
        } else {
            throw "Node.js not found"
        }
    } catch {
        Write-ColorOutput "[WARNING] Node.js 未安装，正在检查 Chocolatey..." "Yellow"

        # 检查 Chocolatey
        if (Get-Command choco -ErrorAction SilentlyContinue) {
            Write-ColorOutput "[INFO] 使用 Chocolatey 安装 Node.js..." "Blue"
            choco install nodejs-lts -y
        } else {
            Write-ColorOutput "[ERROR] 请安装 Node.js: https://nodejs.org" "Red"
            Write-ColorOutput "[INFO] 或使用 Chocolatey: choco install nodejs-lts" "Blue"
            exit 1
        }
    }

    # 重新加载 PATH
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

    # 验证 Node.js
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        Write-ColorOutput "[ERROR] Node.js 安装失败，请重新打开终端后重试" "Red"
        exit 1
    }

    # 检查 Git (npm 安装依赖需要)
    Write-Host ""
    Write-ColorOutput "[INFO] 检查 Git 安装状态..." "Blue"
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-ColorOutput "[WARNING] Git 未安装，正在尝试安装..." "Yellow"

        # 检查 Chocolatey
        if (Get-Command choco -ErrorAction SilentlyContinue) {
            Write-ColorOutput "[INFO] 使用 Chocolatey 安装 Git..." "Blue"
            choco install git -y
            # 重新加载 PATH
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        } else {
            Write-ColorOutput "[ERROR] 请安装 Git: https://git-scm.com/download/win" "Red"
            exit 1
        }
    }

    # 验证 Git
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-ColorOutput "[ERROR] Git 安装失败，请重新打开终端后重试" "Red"
        exit 1
    } else {
        $gitVersion = git --version 2>$null
        Write-ColorOutput "[SUCCESS] Git 已安装: $gitVersion" "Green"
    }

    # 交互模式 - 获取 API Key (隐藏输入)
    if ([string]::IsNullOrEmpty($ApiKey)) {
        Write-Host ""
        Write-ColorOutput "[INFO] 请输入您的 GPUNexus API Key" "Blue"
        Write-ColorOutput "[INFO] 获取方式: 访问 https://gpunexus.com 注册并创建 API Key" "Blue"
        $securePassword = Read-Host "API Key" -AsSecureString
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
        $ApiKey = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        # 显示确认信息
        $keyLen = $ApiKey.Length
        if ($keyLen -le 12) {
            Write-ColorOutput "[INFO] 已接收 API Key: ***" "Blue"
        } else {
            $prefix = $ApiKey.Substring(0, 6)
            $suffix = $ApiKey.Substring($keyLen - 6)
            Write-ColorOutput "[INFO] 已接收 API Key: ${prefix}***${suffix}" "Blue"
        }
    }

    if ([string]::IsNullOrEmpty($ApiKey)) {
        Write-ColorOutput "[ERROR] API Key 不能为空" "Red"
        exit 1
    }

    # 默认 Base URL
    $defaultBaseUrl = ""

    # 交互模式 - 选择模型
    if ($ModelChoice -eq 0) {
        Write-Host ""
        Write-ColorOutput "[INFO] 请选择要使用的模型:" "Blue"
        Write-Host "  1. MiniMax-M2.1 (OpenAI兼容接口)"
        Write-Host "  2. GPUNexus (Claude Code接口)"
        $input = Read-Host "请选择 [1/2] (默认: 2)"
        if ([string]::IsNullOrEmpty($input)) {
            $input = "2"
        }
        $ModelChoice = [int]$input
    }

    switch ($ModelChoice) {
        1 {
            $providerName = "GPUNexus"
            $defaultBaseUrl = "https://api.gpunexus.com/v1"
            $apiType = "openai-completions"
            $modelId = "MiniMax-M2.1"
            Write-ColorOutput "[INFO] 已选择模型: MiniMax-M2.1" "Green"
        }
        2 {
            $providerName = "GPUNexus"
            $defaultBaseUrl = "https://coding.gpunexus.com"
            $apiType = "anthropic-messages"
            $modelId = "GPUNexus"
            Write-ColorOutput "[INFO] 已选择模型: GPUNexus" "Green"
        }
        default {
            Write-ColorOutput "[WARNING] 无效选择，使用默认: GPUNexus" "Yellow"
            $providerName = "GPUNexus"
            $defaultBaseUrl = "https://coding.gpunexus.com"
            $apiType = "anthropic-messages"
            $modelId = "GPUNexus"
        }
    }

    # 交互模式 - 获取 Base URL (仅当未通过命令行参数提供时)
    if ([string]::IsNullOrEmpty($BaseUrl)) {
        Write-Host ""
        Write-ColorOutput "[INFO] 请输入 API Base URL (直接回车使用默认值: ${defaultBaseUrl})" "Blue"
        $inputBaseUrl = Read-Host "Base URL"
        if ([string]::IsNullOrEmpty($inputBaseUrl)) {
            $BaseUrl = $defaultBaseUrl
        } else {
            $BaseUrl = $inputBaseUrl
        }
    }
    $baseUrl = $BaseUrl
    Write-ColorOutput "[INFO] 已设置 Base URL: ${baseUrl}" "Green"

    Write-Host ""
    Write-ColorOutput "============================================" "Blue"
    Write-Host ""

    # 步骤2: 安装 OpenClaw
    Write-ColorOutput ">>> 步骤 2/4: 安装 OpenClaw" "Blue"

    # 设置 npm 镜像源
    npm config set registry $NpmRegistry
    Write-ColorOutput "[INFO] 已设置 npm 镜像源: $NpmRegistry" "Blue"

    # 设置 npm 使用 HTTPS 而不是 SSH 来克隆 git 依赖
    # 解决没有 GitHub SSH 密钥时的安装问题
    Write-ColorOutput "[INFO] 配置 npm 使用 HTTPS 协议克隆 git 依赖..." "Blue"
    npm config set git-tag-version false
    git config --global url."https://github.com/".insteadOf "ssh://git@github.com/" 2>$null
    git config --global url."https://github.com/".insteadOf "git@github.com:" 2>$null

    # 全局安装 openclaw
    npm install -g openclaw

    if (Get-Command openclaw -ErrorAction SilentlyContinue) {
        Write-ColorOutput "[SUCCESS] OpenClaw 安装成功" "Green"
        openclaw --version
    } else {
        Write-ColorOutput "[ERROR] OpenClaw 安装失败" "Red"
        exit 1
    }

    # 步骤3: 创建配置文件
    Write-Host ""
    Write-ColorOutput ">>> 步骤 3/4: 创建配置文件" "Blue"

    # 先运行 openclaw setup 生成默认配置
    Write-ColorOutput "[INFO] 正在运行 openclaw setup..." "Blue"
    openclaw setup

    # 读取现有配置并合并 models 部分
    Write-ColorOutput "[INFO] 正在更新配置文件..." "Blue"

    if (Test-Path $ConfigFile) {
        # 读取现有配置
        $configJson = Get-Content $ConfigFile -Raw | ConvertFrom-Json

        # 添加 models.providers
        $configJson | Add-Member -NotePropertyName "models" -NotePropertyValue ([PSCustomObject]@{
            providers = @{
                $providerName = @{
                    baseUrl = $baseUrl
                    apiKey = $ApiKey
                    auth = "token"
                    api = $apiType
                    headers = @{}
                    authHeader = $true
                    models = @(
                        @{
                            id = $modelId
                            name = $modelId
                            api = $apiType
                            reasoning = $false
                            input = @("text")
                            cost = @{
                                input = 1048576
                                output = 1048576
                                cacheRead = 0
                                cacheWrite = 0
                            }
                            contextWindow = 1048576
                            maxTokens = 1048576
                            compat = @{
                                supportsStore = $false
                                maxTokensField = "max_tokens"
                            }
                        }
                    )
                }
            }
        }) -Force

        # 添加 agents.defaults.model.primary
        if (-not $configJson.agents) {
            $configJson | Add-Member -NotePropertyName "agents" -NotePropertyValue ([PSCustomObject]@{
                defaults = [PSCustomObject]@{
                    model = [PSCustomObject]@{
                        primary = "${providerName}/${modelId}"
                    }
                    models = @{
                        "${providerName}/${modelId}" = @{}
                    }
                }
            }) -Force
        } else {
            $configJson.agents.defaults | Add-Member -NotePropertyName "model" -NotePropertyValue ([PSCustomObject]@{
                primary = "${providerName}/${modelId}"
            }) -Force
            $configJson.agents.defaults | Add-Member -NotePropertyName "models" -NotePropertyValue @{
                "${providerName}/${modelId}" = @{}
            } -Force
        }

        # 保存更新后的配置
        $configJson | ConvertTo-Json -Depth 10 | Out-File -FilePath $ConfigFile -Encoding utf8
        Write-ColorOutput "[SUCCESS] 配置文件已更新: ${ConfigFile}" "Green"
    } else {
        Write-ColorOutput "[ERROR] 配置文件未找到: ${ConfigFile}" "Red"
        exit 1
    }

    # 步骤4: 初始化配置
    Write-Host ""
    Write-ColorOutput ">>> 步骤 4/4: 初始化配置" "Blue"

    Write-ColorOutput "[SUCCESS] 部署完成!" "Green"
    Write-Host ""
    Write-ColorOutput "============================================" "Blue"
    Write-Host ""
    Write-ColorOutput "[INFO] 配置文件位置: ${ConfigFile}" "Blue"
    Write-ColorOutput "[INFO] 访问地址: http://127.0.0.1:18789/" "Blue"
    Write-ColorOutput "[INFO] Token: 查看配置文件中的 gateway.auth.token 字段" "Blue"
    Write-Host ""
    Write-ColorOutput "[WARNING] 即将运行 openclaw onboard 进行初始化配置..." "Yellow"
    Write-ColorOutput "[INFO] 提示: onboard 会重置并重新配置服务" "Blue"
    Write-Host ""

    # 运行 onboard 进行初始化配置（会重置并重新配置服务）
    openclaw onboard
}

# 运行主函数
Main
