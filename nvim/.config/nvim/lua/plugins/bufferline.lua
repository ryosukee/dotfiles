return {
  {
    "akinsho/bufferline.nvim",
    opts = {
      options = {
        -- diffview hooks から showtabline を制御するため auto_toggle を無効化
        -- diffview が開く前の showtabline 値を保存し、閉じたときに復元する
        auto_toggle_bufferline = false,
      },
    },
  },
}
