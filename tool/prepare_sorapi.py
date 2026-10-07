"""Slice approved sprite artwork offline; never synthesize character variants."""
from pathlib import Path
import json
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / 'design/sorapi/source-sheet.png'
OUT = ROOT / 'assets/mascot/sorapi'
# User-provided sprite sheet: exclude headings and labels from each source cell.
CELLS = {
    'idle': (8, 259, 106, 371),
    'blink': (109, 259, 200, 371),
    'look': (202, 254, 290, 371),
    'wait': (377, 43, 493, 180),
    'sit': (601, 270, 695, 373),
    'sleep': (696, 251, 816, 372),
    'wave': (10, 448, 116, 570),
    'jump': (380, 426, 491, 562),
    'happy': (493, 442, 600, 570),
    'trouble': (1177, 251, 1276, 371),
    'think': (1275, 240, 1355, 370),
    'book': (1199, 444, 1304, 570),
    'discover': (1307, 423, 1435, 569),
    **{f'walk_{i}': (515+i*101, 61, 617+i*101, 182) for i in range(5)},
}

def main():
    sheet = Image.open(SOURCE).convert('RGBA')
    OUT.mkdir(parents=True, exist_ok=True)
    for name, bounds in CELLS.items():
        sprite = sheet.crop(bounds)
        # Remove narrow fragments of neighbouring cells at the crop edges.
        alpha = sprite.getchannel('A')
        visited = set()
        for y in range(sprite.height):
            for x in range(sprite.width):
                if (x, y) in visited or alpha.getpixel((x, y)) < 220:
                    continue
                todo, component = [(x, y)], []
                visited.add((x, y))
                while todo:
                    px, py = todo.pop()
                    component.append((px, py))
                    for nx, ny in [(px-1,py),(px+1,py),(px,py-1),(px,py+1)]:
                        if 0 <= nx < sprite.width and 0 <= ny < sprite.height and (nx,ny) not in visited and alpha.getpixel((nx,ny)) >= 220:
                            visited.add((nx,ny)); todo.append((nx,ny))
                xs = [p[0] for p in component]
                if (min(xs) <= 2 or max(xs) >= sprite.width-3) and max(xs)-min(xs) < 18:
                    ys = [p[1] for p in component]
                    for py in range(max(0,min(ys)-2),min(sprite.height,max(ys)+3)):
                        for px in range(max(0,min(xs)-2),min(sprite.width,max(xs)+3)):
                            sprite.putpixel((px,py), (0,0,0,0))
        box = sprite.getchannel('A').getbbox()
        assert box, name
        sprite = sprite.crop(box)
        sprite.thumbnail((110, 130), Image.Resampling.NEAREST)
        frame = Image.new('RGBA', (128, 144))
        frame.alpha_composite(sprite, ((128-sprite.width)//2, 140-sprite.height))
        frame.save(OUT / f'{name}.png', optimize=True)
    (ROOT / 'design/sorapi/crops.json').write_text(json.dumps(CELLS, indent=2), encoding='utf-8')

if __name__ == '__main__':
    main()
