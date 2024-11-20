return {
  black = 0xff282a36,
  white = 0xfff8f8f2,
  red = 0xffff5555,
  green = 0xff50fa7b,
  blue = 0xff8be9fd,
  yellow = 0xfff1fa8c,
  orange = 0xffffb86c,
  magenta = 0xfff694ff,
  grey = 0xff6d6d6d,
  teal = 0xff82e2ff,
  purple = 0xffbd93f9,
  transparent = 0x00000000,
  pink = 0xffff79c6,
  comment = 0xff6272a4,
  -- Dracula colors
  -- Background=0xff282a36
  -- Line_Highlight=0xff44475a

  bar = {
    bg = 0xe621202e,
    border = 0xff29263c,
  },
  popup = {
    bg = 0xe621202e,
    border = 0xff6d6d6d
  },
  spaces = {
    active = 0xff3d375e,
    inactive = 0x0029263c
  },
  bg1 = 0xff15141b,
  bg2 = 0xff29263c,

  with_alpha = function(color, alpha)
    if alpha > 1.0 or alpha < 0.0 then return color end
    return (color & 0x00ffffff) | (math.floor(alpha * 255.0) << 24)
  end,
}
