# Contributing (日本語)

開発の詳しい手順は [README.ja.md の「開発者向け」節](README.ja.md#開発者向け-pkgdevelop-でキットを編集する) を参照。ここでは PR を出す前に確認してほしい要点だけをまとめる。

## 動作環境

開発・検証は macOS のみ (他 OS は未検証)。Julia 1.12 以上が必要 (CI は `1.12` と `~1.13.0-0` の両方でテストしている)。リモートホスト関連の変更には、各ホストに Julia 1.12+、ローカル側に Git・OpenSSH (`ssh`)・rsync が必要 (詳細は README の[リモートホストを使う](README.ja.md#リモートホストを使う)節)。

メモ: 実装上は `ssh`/`rsync`/POSIX コマンド (`find` など) を前提にしているため、ローカル・リモートとも理論上動きそうなのは macOS と Linux。Windows は `src/DistSSHKit/display.jl` のパス区切り文字表示 (`Sys.iswindows()`) 以外に考慮箇所がなく、非対応 (WSL 経由なら動く可能性はある)。`--local` のみで SSH を使わない場合は OS 非依存のはずだが未検証。

## セットアップ

```bash
git clone https://github.com/daihiko-lab/DistSSHKit.jl.git ~/dev/DistSSHKit.jl
cd ~/dev/DistSSHKit.jl
```

キット単体で開発する場合はこのままでよい。自分のプロジェクトから編集して試したい場合は `Pkg.develop(path=...)` で参照する (README 参照)。

## ブランチ・コミット

- `main` に直接 push しない (ブランチ保護で拒否される)。`feature/xxx`, `fix/xxx`, `docs/xxx`, `chore/xxx` のようなブランチを切って PR を出す
- 破壊的変更 (CLI サブコマンド名、モジュール名、driver 契約 `init_output_dir!`/`main` など) を含む場合は、`Project.toml` の `version` の `0.x.y` の `x` を上げる。パッチ `y` は非破壊的変更のみ (Julia の SemVer 運用では `0.x` 系は `x` が事実上のメジャー番号として扱われる。詳細は README 参照)

## PR を出す前に

```bash
# 1. テスト
julia --project=. -e 'using Pkg; Pkg.test()'

# 2. 静的解析 (参考程度。jetls が PATH にあること。ファイル構成が変わったら
#    .github/workflows/jetls.yml の同じコマンドも合わせて更新すること)
jetls check demos/*.jl src/DistSSHKit.jl src/runner.jl src/setup.jl src/suggest_workers.jl test/*.jl test/fixtures/*.jl

# 3. 手動スモーク (README クイックスタートと同じ)
julia --project=. -m DistSSHKit runner --local 2 demos/param_sweep.jl
julia --project=. -m DistSSHKit runner --local 2 demos/coin_flip.jl

# 4. リモート実行に関わる変更 (runner/setup 周り) をしたときは、実機のホストでも確認する
julia --project=. -m DistSSHKit setup --check HOST ...
julia --project=. -m DistSSHKit runner HOST:2 demos/param_sweep.jl
```

`Pkg.test()` は demo スクリプト自体 (`test/test_demos.jl`) と `demo install`/`demo list` (`test/test_demo_cli.jl`) を両方カバーする。2, 3 は push 前の追加確認。4 は `--local` では検証できない SSH 経由の挙動 (接続、git 同期、ワーカー起動など) を触った場合のみ必須。

CI (`test (1.12)`, `test (~1.13.0-0)`) が pass しないとマージできない (ブランチ保護)。`jetls` は必須チェックではなく参考情報として使う。

## マージ

- レビュー承認は必須ではないが、変更内容が伝わる PR 説明を書く (このリポジトリの PR テンプレートに従う)
- マージ後にタグ (`vX.Y.Z`) が必要な変更かどうかは、メンテナ (`yamanori99`) が判断する

## 言語について

- コードファイル (`.jl`) 内 (コメント、docstring、エラーメッセージなど) は基本的に英語のみ
- ドキュメント (README、CONTRIBUTING など) は英語 + 日本語のセットを維持する。開発者が日本語環境にいることが多いため。新規ドキュメントを追加・変更するときは、`*.ja.md` (または対応する日本語版) も合わせて更新すること
- ドキュメントの日本語版・英語版どちらも生成AIによる作成を認めるが、内容は必ず自分で確認すること (下記「生成AIを用いた開発」を参照)

## 生成AIを用いた開発

このリポジトリは生成AI (LLM) を使った開発を許容している。PR を出す際は、AI で生成したコードやドキュメントでも「自分が内容を理解し、動作確認した」上で出すこと (レビューなしの vibe-coding は避ける)。背景は README の[生成AIを用いた開発](README.ja.md#生成aiを用いた開発)節を参照。また、ドキュメント内の過度な表現や装飾を避けること。
