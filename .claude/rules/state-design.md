# 永続 state 設計: derive できるものは store しない

dotfiles 内のスクリプト (`claude/.claude/statusline.sh` 等) が持つ
永続 state は最小限に留める。入力から毎回 derive できる値を state に
含めると整合性ズレで検知困難なバグになる。

## 原則

state に持つべきもの:

- 過去の観測値 (例: 各 day の朝の weekly_pct)
- user の選択 (preferences)
- 積算/履歴 (そのままでは再現できないもの)

state に持たないもの:

- 入力 (Claude Code が渡す JSON, env 変数, API レスポンス) から
  毎回得られる値
- 他のフィールドから計算できる派生値
- 現在時刻から決まる値 (remaining 系、経過時間)

## statusline.sh v3 → v4 の教訓

**v3 (壊れていた設計)**: `cycle.ends_at`, `cycle.day_idx`,
`cycle.day_start_epoch`, `cycle.base_pct`, `cycle.last_pct`,
`cycle.ts_observed`, `days[]` を全て state に保持。

発生した実害:

- `ends_at` だけ新 cycle、`day_idx` は旧 cycle のまま → 「14:00 を
  過ぎても today が更新されない」状態に陥る
- sanity check (`stored_base > current_pct` なら base=current) が
  stale 入力で base を壊す
- 並行実行・部分更新で tmp ファイルが複数残留
- day_idx 振動 (6↔7) で finalize が繰り返し発動

**v4 (修正後)**:

```json
{
  "version": 4,
  "history": [
    { "day_start_ts": ..., "morning_pct": ... }
  ]
}
```

`ends_at`, `day_idx`, `day_start_epoch`, `last_pct`, `ts_observed` は
全て削除。毎回 Claude Code の JSON (`rate_limits.seven_day.resets_at`)
と現在時刻から derive。

state 書き込みトリガは「day 進行」「cycle 切替」「初回」のみ。
従来は毎 run 書き込みだったが、ほぼ 1 日 1 回に激減。race も
tmp 残留もほぼ起きない。

## 設計時の問い (state フィールドを追加する前に必ず)

1. この値は入力から毎回 derive できるか? → できるなら store しない
2. 他のフィールドから計算できるか? → できるなら store しない
3. 本当に履歴が必要か? 最新値だけでいいか?
4. state 書き込み頻度は最小化できているか? (毎 run 書くと race 元)

state が複雑化してきたら、**フィールド単位で上記問いを繰り返して
削れるものを削る**。冗長な state ほどバグが混入しやすい。
