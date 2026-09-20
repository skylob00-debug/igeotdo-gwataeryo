# -*- coding: utf-8 -*-
"""앱 아이콘·스플래시 원본을 만든다.

    .venv/Scripts/python.exe tools/make_brand.py --concepts      # 시안 비교 시트
    .venv/Scripts/python.exe tools/make_brand.py --feature       # 스토어 그래픽
    .venv/Scripts/python.exe tools/make_brand.py                 # 원본 (물음표 단독)
    .venv/Scripts/python.exe tools/make_brand.py --icon coin     # 점을 원화로 (음각)
    .venv/Scripts/python.exe tools/make_brand.py --icon solid    # 점을 원화로 (양각)

만드는 것
    app/assets/brand/icon.png         1024  스토어·iOS (투명도 없음)
    app/assets/brand/icon_fg.png       432  Android 적응형 전경 (투명)
    app/assets/brand/splash_mark.png   512  스플래시 마크 (투명, 오렌지)
    design/icon_concepts.png                시안 비교 (--concepts)
    design/store/feature.png          1024x500  Play 그래픽 이미지 (--feature)

아이콘을 손으로 그리지 않고 스크립트로 두는 이유는, 색을 바꾸거나 다른 안으로
갈아탈 때 전 크기를 다시 뽑아야 하기 때문이다. 색은 app/lib/core/theme.dart 의
AppColors 와 같은 값이다. 한쪽만 바꾸면 스플래시에서 홈으로 넘어갈 때 색이 튄다.
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
BRAND = ROOT / "app" / "assets" / "brand"
DESIGN = ROOT / "design"

# theme.dart 의 AppColors 와 같은 값
PAPER = (255, 253, 249)      # paper      스플래시 바탕 = 앱 첫 화면 바탕
INK = (34, 36, 42)           # ink
ORANGE = (249, 115, 22)      # accentIcon
DEEP = (180, 71, 15)         # accentSolid
WHITE = (255, 255, 255)
RED = (198, 40, 40)

# 물음표는 굵고 획이 고른 산세리프면 된다. 맑은고딕은 '?' 글리프가 좁다.
FONT_QUESTION = "C:/Windows/Fonts/arialbd.ttf"
FONT_KR = "C:/Windows/Fonts/malgunbd.ttf"


def _gradient(size: int, top, bottom) -> Image.Image:
    """세로 그라데이션. 단색보다 작은 크기에서 덜 납작해 보인다."""
    strip = Image.new("RGB", (1, size))
    d = ImageDraw.Draw(strip)
    for y in range(size):
        t = y / (size - 1)
        d.point((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return strip.resize((size, size))


def _centered(draw, xy, text, font, fill) -> None:
    """글리프의 실제 먹는 영역 기준으로 가운데. 베이스라인 기준이 아니다."""
    l, t, r, b = draw.textbbox((0, 0), text, font=font)
    draw.text((xy[0] - (l + r) / 2, xy[1] - (t + b) / 2), text, font=font, fill=fill)


def mark(size: int, color) -> Image.Image:
    """배경 없는 물음표. 스플래시와 적응형 전경이 쓴다."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    _centered(d, (size / 2, size / 2 - size * 0.015), "?",
              ImageFont.truetype(FONT_QUESTION, int(size * 0.70)), color)
    return img


def _question_layer(size: int, drop_dot: bool = False):
    """물음표 레이어와 아래 점의 위치를 함께 준다.

    점의 좌표를 눈대중으로 박지 않고 알파값에서 찾는다. 글꼴이나 크기를
    바꿔도 따라온다. 물음표 글리프는 갈고리와 점 사이가 빈 줄로 갈라진다.
    """
    img = mark(size, WHITE)
    alpha = img.split()[3]
    rows = [y for y in range(size) if alpha.crop((0, y, size, y + 1)).getbbox()]
    gap = next((rows[i + 1] for i in range(len(rows) - 1)
                if rows[i + 1] - rows[i] > 1), None)
    if gap is None:                       # 갈라지지 않으면 점을 건드리지 않는다
        return img, None
    box = alpha.crop((0, gap, size, rows[-1] + 1)).getbbox()
    dot = (box[0], gap, box[2], rows[-1] + 1)
    if drop_dot:
        img.paste((0, 0, 0, 0), dot)
    return img, dot


def _draw_won(draw, cx, cy, width, fill, bar) -> None:
    """원화를 직접 그린다. 물음표와 같은 글꼴의 W 에 가로줄 둘.

    글꼴의 ￦ 글리프를 쓰지 않는 이유는 획이 물음표보다 가늘어
    한 아이콘 안에서 굵기가 어긋나 보이기 때문이다.
    """
    probe = ImageFont.truetype(FONT_QUESTION, 100)
    l, t, r, b = draw.textbbox((0, 0), "W", font=probe)
    font = ImageFont.truetype(FONT_QUESTION, max(1, int(100 * width / (r - l))))
    l, t, r, b = draw.textbbox((0, 0), "W", font=font)
    gw, gh = r - l, b - t
    draw.text((cx - (l + r) / 2, cy - (t + b) / 2), "W", font=font, fill=fill)
    for frac in (0.30, 0.58):
        y = cy - gh / 2 + gh * frac
        draw.rectangle([cx - gw / 2 * 1.08, y - bar / 2,
                        cx + gw / 2 * 1.08, y + bar / 2], fill=fill)


# --- 시안 ------------------------------------------------------------------

def concept_plain(size: int) -> Image.Image:
    """1. 물음표 단독 (확정안)."""
    img = _gradient(size, ORANGE, DEEP)
    m = mark(size, WHITE)
    img.paste(m, (0, 0), m)
    return img


def concept_won_coin(size: int) -> Image.Image:
    """2. 물음표 점을 동그라미로 키우고 그 안에 원화를 뚫는다 (음각).

    점의 둥근 덩어리가 그대로 남아 물음표 실루엣이 깨지지 않는다.
    대신 원화는 72px 아래에서 뭉개져 사실상 점으로 보인다.
    """
    layer, dot = _question_layer(size, drop_dot=True)
    cx, cy = (dot[0] + dot[2]) / 2, (dot[1] + dot[3]) / 2
    r = (dot[2] - dot[0]) / 2 * 1.50
    mask = Image.new("L", (size, size), 0)
    md = ImageDraw.Draw(mask)
    md.ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
    _draw_won(md, cx, cy + r * 0.03, r * 1.02, 0, r * 0.125)
    layer.paste(Image.new("RGBA", (size, size), WHITE + (255,)), (0, 0), mask)
    img = _gradient(size, ORANGE, DEEP)
    img.paste(layer, (0, 0), layer)
    return img


def concept_won_solid(size: int) -> Image.Image:
    """2-2. 점 자리에 굵은 흰 원화를 그대로 놓는다 (양각).

    큰 크기에서는 돈이라는 뜻이 훨씬 분명하다. 대신 아래가 옆으로 넓어져
    작은 크기에서 물음표 실루엣이 덜 또렷하다.
    """
    layer, dot = _question_layer(size, drop_dot=True)
    cx, cy = (dot[0] + dot[2]) / 2, (dot[1] + dot[3]) / 2
    h = dot[3] - dot[1]
    _draw_won(ImageDraw.Draw(layer), cx, cy + h * 0.05,
              (dot[2] - dot[0]) * 1.55, WHITE + (255,), h * 0.20)
    img = _gradient(size, ORANGE, DEEP)
    img.paste(layer, (0, 0), layer)
    return img


def concept_notice(size: int) -> Image.Image:
    """3. 고지서 + 물음표."""
    img = _gradient(size, ORANGE, DEEP)
    d = ImageDraw.Draw(img)
    x0, y0, x1, y1 = size * 0.24, size * 0.17, size * 0.76, size * 0.83
    d.rounded_rectangle([x0, y0, x1, y1], radius=size * 0.05, fill=WHITE)
    for frac in (0.30, 0.38):
        d.rounded_rectangle([x0 + size * 0.07, y0 + size * frac,
                             x1 - size * 0.07, y0 + size * frac + size * 0.035],
                            radius=size * 0.02, fill=(238, 232, 222))
    _centered(d, (size / 2, size * 0.62), "?",
              ImageFont.truetype(FONT_QUESTION, int(size * 0.30)), DEEP)
    return img


def concept_sign(size: int) -> Image.Image:
    """4. 표지판형. 공공기관 앱으로 오인될 소지가 있어 쓰지 않는다."""
    img = Image.new("RGB", (size, size), PAPER)
    d = ImageDraw.Draw(img)
    m, w = size * 0.10, size * 0.085
    d.ellipse([m, m, size - m, size - m], outline=RED, width=int(w))
    _centered(d, (size / 2, size / 2 - size * 0.015), "?",
              ImageFont.truetype(FONT_QUESTION, int(size * 0.48)), INK)
    return img


# 아이콘 원본으로 쓸 수 있는 안. --icon 으로 고른다.
ICONS = {
    "plain": concept_plain,
    "coin": concept_won_coin,
    "solid": concept_won_solid,
}

CONCEPTS = [
    ("1. 물음표 단독", concept_plain),
    ("2. 점을 동그라미 원화로 (음각)", concept_won_coin),
    ("2-2. 점을 굵은 원화로 (양각)", concept_won_solid),
    ("3. 고지서 + 물음표", concept_notice),
    ("4. 표지판형 (비추천)", concept_sign),
]


def _masked(img: Image.Image, size: int = 128) -> Image.Image:
    """적응형 아이콘 원형 마스크에서 어떻게 잘리는지."""
    out = Image.new("RGB", (size, size), (246, 244, 240))
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, size - 1, size - 1], fill=255)
    out.paste(img.convert("RGB").resize((size, size), Image.LANCZOS), (0, 0), mask)
    return out


def write_concepts() -> None:
    pad, cell, label = 28, 256, 46
    w = pad + (cell + pad) * len(CONCEPTS)
    h = pad + label + cell + 20 + 128 + pad
    sheet = Image.new("RGB", (w, h), (246, 244, 240))
    d = ImageDraw.Draw(sheet)
    font = ImageFont.truetype(FONT_KR, 19)
    for i, (name, fn) in enumerate(CONCEPTS):
        img = fn(512)
        x = pad + (cell + pad) * i
        d.text((x, pad + 6), name, font=font, fill=INK)
        sheet.paste(img.convert("RGB").resize((cell, cell), Image.LANCZOS), (x, pad + label))
        sheet.paste(_masked(img), (x + (cell - 128) // 2, pad + label + cell + 20))
    DESIGN.mkdir(parents=True, exist_ok=True)
    out = DESIGN / "icon_concepts.png"
    sheet.save(out)
    print(f"-> {out}")


def _cutout(make, size: int, color) -> Image.Image:
    """시안에서 바탕을 걷어내고 마크만 남긴다.

    시안은 오렌지 바탕 위 흰 마크다. 마크만 따로 그리는 함수를 안마다
    또 두면 둘이 어긋나므로, 같은 그림에서 밝기로 갈라낸다.
    오렌지(#F97316)는 회색조로 약 144, 흰색은 255라 넉넉히 갈린다.
    """
    src = make(size).convert("RGB")
    alpha = src.convert("L").point(lambda v: 255 if v > 200 else 0)
    out = Image.new("RGBA", (size, size), color + (0,))
    out.putalpha(alpha)
    return out


def write_brand(choice: str = "plain") -> None:
    """확정안의 원본을 뽑는다. choice 는 ICONS 의 열쇠."""
    BRAND.mkdir(parents=True, exist_ok=True)
    make = ICONS[choice]

    # 스토어·iOS. 투명도가 있으면 App Store 심사에서 걸린다.
    make(1024).convert("RGB").save(BRAND / "icon.png")

    # Android 적응형 전경. 바탕은 adaptive_icon_background 가 칠하므로 마크만.
    #
    # 구도를 icon.png 와 똑같이 둔다. 물음표가 캔버스의 50% 를 먹으므로
    # 108dp 기준 54dp 다. 72dp 안전영역 안에 들어가고 네모 아이콘과도
    # 크기가 맞는다. pubspec 의 adaptive_icon_foreground_inset 을 0 으로
    # 두는 것이 짝이다 — 기본값 16% 를 그대로 두면 마크가 한 번 더 줄어
    # 네모 아이콘보다 눈에 띄게 작아진다.
    _cutout(make, 432, WHITE).save(BRAND / "icon_fg.png")

    # 스플래시 마크. 종이색 바탕 위에 올라가므로 오렌지.
    # iOS 와 Android 11 이하는 이 그림을 그대로 가운데 놓는다.
    _cutout(make, 512, ORANGE).save(BRAND / "splash_mark.png")

    # Android 12 이상은 시스템이 그린다. 규격이 따로 있다.
    # 1152x1152 캔버스에, 가운데 지름 768 원 안만 보인다. 바깥은 잘린다.
    #
    # 마크가 그 원의 6할쯤을 먹게 잡는다. 캔버스에 맞춰 작게 그리면
    # 다른 앱 아이콘 사이에서 혼자 쪼그라들어 보인다.
    # icon_background_color 는 쓰지 않는다 — 그것을 주면 보이는 영역이
    # 768 에서 512 로 줄고, 종이색 위에 종이색 원을 얹는 셈이라 값도 없다.
    canvas = 1152
    inner = 960                      # 마크 높이 = inner 의 절반 = 480 (768 의 62%)
    big = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    m12 = _cutout(make, inner, ORANGE)
    big.paste(m12, ((canvas - inner) // 2, (canvas - inner) // 2), m12)
    big.save(BRAND / "splash_android12.png")

    for name in ("icon.png", "icon_fg.png", "splash_mark.png",
                 "splash_android12.png"):
        p = BRAND / name
        print(f"-> {p}  ({p.stat().st_size / 1024:.0f} KB)")


def write_feature() -> None:
    """Play 스토어 그래픽 이미지. 1024x500.

    스토어 목록에서 아이콘 위에 걸리는 띠다. 여기에 긴 글을 넣으면
    작은 화면에서 안 읽힌다. 마크 + 두 줄이면 족하다.

    가로로 길지만 기기마다 양 끝이 잘린다. 가운데에 몰아 두고
    좌우 120px 안쪽에는 아무것도 두지 않는다.
    """
    W, H = 1024, 500
    img = _gradient(W, ORANGE, DEEP).rotate(-90, expand=True).resize((W, H))
    d = ImageDraw.Draw(img)

    big = ImageFont.truetype(FONT_KR, 66)
    small = ImageFont.truetype(FONT_KR, 28)
    title, sub = "이것도 과태료?", "몰랐다가 무는 과태료를 미리"

    mark_w, gap = 230, 38
    tw = d.textbbox((0, 0), title, font=big)[2]
    sw = d.textbbox((0, 0), sub, font=small)[2]
    block = mark_w + gap + max(tw, sw)
    x0 = (W - block) // 2

    mark = _cutout(ICONS["coin"], mark_w, WHITE)
    img.paste(mark, (x0, (H - mark_w) // 2), mark)

    tx = x0 + mark_w + gap
    d.text((tx, H // 2 - 62), title, font=big, fill=WHITE)
    d.text((tx, H // 2 + 22), sub, font=small, fill=(255, 226, 205))

    out = DESIGN / "store" / "feature.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out)
    print(f"-> {out}  ({img.size[0]}x{img.size[1]})")


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    if "--concepts" in sys.argv:
        write_concepts()
        return
    if "--feature" in sys.argv:
        write_feature()
        return
    choice = "plain"
    if "--icon" in sys.argv:
        choice = sys.argv[sys.argv.index("--icon") + 1]
        if choice not in ICONS:
            raise SystemExit(f"--icon 은 {', '.join(ICONS)} 중 하나")
    print(f"아이콘 안: {choice}")
    write_brand(choice)


if __name__ == "__main__":
    main()
