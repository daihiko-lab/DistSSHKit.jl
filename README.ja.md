# ParallelRunnerKit.jl

[![CI](https://github.com/daihiko-lab/ParallelRunnerKit.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/daihiko-lab/ParallelRunnerKit.jl/actions/workflows/CI.yml)
[![Julia 1.12+](https://img.shields.io/badge/Julia-1.12+-blue.svg)](https://julialang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

任意の Julia ドライバスクリプトを、ローカル/SSH リモートの **プロセス** に分散実行する (Distributed.jl。マルチスレッドではない)。

English: [README.md](README.md)

**状態:** `0.x` (1.0 未満)。マイナー版の間でもインターフェースが変わる可能性がある。

## インストール

```bash
git clone https://github.com/daihiko-lab/ParallelRunnerKit.jl.git
cd ParallelRunnerKit.jl
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

他アプリへの埋め込み (サブモジュール等) は [埋め込み](#埋め込み) を参照。

## ドライバスクリプト

`runner.jl` で動かすスクリプトは、`Main` に次の 2 関数だけを定義する:

```julia
# ワーカー追加**前**に呼ばれる。ENV["DISTRIBUTED_OUTPUT_DIR"] を設定する。
function init_output_dir!(args::Vector{String})::String
    ...
end

# ワーカー準備**後**に呼ばれる。nworkers()/workers() を見て pmap 等を使う。
function main()
    ...
end
```

動く最小例: [`templates/script_template.jl`](templates/script_template.jl)。

## クイックスタート

```bash
# 1. リモートへ clone + 依存インストール (初回のみ)
julia --project=. setup.jl --clone HOST1 HOST2 ...
julia --project=. setup.jl --instantiate HOST1 HOST2 ...

# 2. コミット後にコード同期
julia --project=. setup.jl --sync HOST1 HOST2 ...

# 3. 実行: ローカル N + リモート各ホスト W ワーカー
julia --project=. runner.jl --local N HOST1:W HOST2:W ... path/to/script.jl [args...]
```

テンプレートで試す:

```bash
julia --project=. runner.jl --local 2 templates/script_template.jl
```

オプション・環境変数の一覧:

```bash
julia --project=. runner.jl --help
julia --project=. setup.jl --help
julia --project=. suggest_workers.jl --help
```

## 前提

- macOS (開発・検証はここのみ。他 OS は未検証)
- リモートへの SSH 鍵認証、Git・Julia がリモートに入っていること
- 全ホストで同じリポジトリパス (異なる場合は `--remote-path` / `DISTRIBUTED_REMOTE_PROJECT_ROOT`)

## 埋め込み

```bash
git submodule add https://github.com/daihiko-lab/ParallelRunnerKit.jl.git ParallelRunnerKit
```

このリポジトリの `[deps]` をホストの `Project.toml` にマージし、スクリプトパスに `ParallelRunnerKit/` を付ける (例: `ParallelRunnerKit/runner.jl`)。ドライバには上記の `init_output_dir!` / `main()` を実装する。ワーカーで load するモジュール名がホストの `name` と違う場合は `runner.jl --package NAME`。

## トラブルシューティング

| 問題 | 対処 |
|------|------|
| ホスト間で git ハッシュ不一致 | `setup.jl --sync` または `--pull` |
| リモートで Julia 未検出 | `--julia PATH` または `JULIA_DISTRIBUTED_EXE` |
| 残骸ワーカー | `setup.jl --cleanup` |
| `attempt to send to unknown socket` | `DISTRIBUTED_INIT_DELAY_SEC=10` |

## ライセンス

MIT — [`LICENSE`](LICENSE)
