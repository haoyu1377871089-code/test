#ifndef __NVBOARD_AT_SCANCODE_H__
#define __NVBOARD_AT_SCANCODE_H__

#define CONCAT_INNER(a, b) a##b
#define CONCAT(a, b) CONCAT_INNER(a, b)
#define concat(a, b) CONCAT(a, b)

#define SDL_PREFIX_INNER(x) SDL_SCANCODE##x
#define SDL_PREFIX(x) SDL_PREFIX_INNER(x)

#define MAP(list, func)
#define SCANCODE_LIST

#define AT_PREFIX(x) 0
#define GET_FIRST(x) 0
#define GET_SECOND(x) 0

#endif
