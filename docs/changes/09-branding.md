# 09 — The icon and the logo

## The problem

The browser tab showed the default Next.js icon, and the sidebar showed a generic
CoreUI lightning bolt. Neither said which application this is.

## The mark

One hub reaching three machines — what the panel does, drawn rather than lettered:

```
        ●
        │
        ●
       ╱ ╲
      ●   ●
```

A monogram was considered and dropped: "M" is not distinctive, and at 16 pixels
the only things that survive are a few heavy dots and strokes.

White on a rounded tile in the brand orange (`#ea580c`). The tile carries its own
background so the mark keeps its contrast on a light or a dark browser chrome,
which a bare glyph does not.

One design detail worth knowing before moving anything: the hub sits at `y=17.9`,
not in the middle. Three arms around a centre are never square with their own
bounding box — two are low, one is high — so a mark centred on its hub reads as
sitting too high in the tile. The first attempt did exactly that.

## Files

| File | For |
|---|---|
| `app/icon.svg` | The tab icon; sharp at any size |
| `app/favicon.ico` | For clients that request `/favicon.ico` directly, 32×32 |
| `components/AppLogo.tsx` | The same mark inside the application |
| `scripts/make-favicon.py` | Generates the `.ico` |

Next.js picks both up from its file conventions:

```html
<link rel="icon" href="/favicon.ico" sizes="32x32" type="image/x-icon"/>
<link rel="icon" href="/icon.svg" sizes="any" type="image/svg+xml"/>
```

The script exists because a binary asset with no source is one nobody can change.
Its geometry is the SVG's geometry, and if one moves the other has to move with it.
It renders at 8× and boxes down for antialiasing, composites the white mark **over
the tile** rather than over transparency — otherwise every edge fringes grey — and
writes the PNG and ICO headers by hand, so it needs nothing installed.

## In the application

`AppLogo` takes a tone. `brand` is the orange tile, used in the sidebar on a light
surface. `inverse` is a translucent white tile, used on the sign-in page, where an
orange tile would disappear into the orange gradient behind it.

It is a component rather than an `<img>` of the SVG file because the tile changes
colour between those two places, and a raster or an external SVG can do neither.

## Cleanup

`public/next.svg`, `vercel.svg`, `globe.svg`, `window.svg` and `file.svg` were
`create-next-app` leftovers, referenced by nothing. The directory was empty
afterwards and went with them.

## Not done

`apple-icon`, the iOS home-screen icon. Next can generate one from code via
`next/og`, but this is an internal operations panel and nobody is adding it to a
phone's home screen. Cheap to add if that changes.
