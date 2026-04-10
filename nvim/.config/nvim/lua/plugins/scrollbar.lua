return {
  {
    "petertriho/nvim-scrollbar",
    event = "BufReadPost",
    opts = {
      handle = {
        blend = 30,
      },
      handlers = {
        gitsigns = true,
        search = false,
      },
    },
  },
}
