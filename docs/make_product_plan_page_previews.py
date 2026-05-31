from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import textwrap

from build_product_documents import (
    OUT,
    SOURCES,
    SOURCE_APPENDIX_BULLETS,
    SOURCE_APPENDIX_ISSUE_BULLETS,
    SOURCE_APPENDIX_VERIFICATION_BULLETS,
    expand_plan_pages,
    HANDOFF_PAGES,
    execution_deepening_sections,
    handoff_deepening_sections,
)


FONT_DIR = Path(r"C:\Windows\Fonts")
REG = str(FONT_DIR / "arial.ttf")
BOLD = str(FONT_DIR / "arialbd.ttf")


def font(path, size):
    try:
        return ImageFont.truetype(path, size)
    except Exception:
        return ImageFont.load_default()


F_TITLE = font(BOLD, 17)
F_H2 = font(BOLD, 11)
F_BODY = font(REG, 9)
F_BOLD = font(BOLD, 9)
F_SMALL = font(REG, 10)
F_FOOT = font(REG, 10)


def wrap(draw, text, font_obj, width):
    words = text.replace("\n", " ").split()
    lines, current = [], ""
    for word in words:
        candidate = f"{current} {word}".strip()
        if draw.textbbox((0, 0), candidate, font=font_obj)[2] <= width:
            current = candidate
        else:
            if current:
                lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines


def draw_wrapped(draw, x, y, text, font_obj, width, fill=(22, 28, 35), line_gap=1, bullet=False):
    prefix = "• " if bullet else ""
    indent = 22 if bullet else 0
    for idx, line in enumerate(wrap(draw, text, font_obj, width - indent)):
        draw.text((x + (indent if idx else 0), y), (prefix if idx == 0 else "  ") + line, font=font_obj, fill=fill)
        y += font_obj.size + line_gap
    return y


def plan_page_to_lines(page):
    blocks = [("title", f"Page {page['number']}: {page['title']}"), ("body", f"Purpose: {page['lead']}")]
    for section in page["sections"]:
        blocks.append(("h2", section["heading"]))
        blocks.append(("body", section["body"]))
        for item in section["bullets"]:
            blocks.append(("bullet", item))
    for section in execution_deepening_sections(page):
        blocks.append(("h2", section["heading"]))
        blocks.append(("body", section["body"]))
        for item in section["bullets"]:
            blocks.append(("bullet", item))
    blocks.append(("h2", "Completion goals for this page"))
    for goal in page["goals"]:
        blocks.append(("bullet", goal))
    return blocks


def handoff_page_to_lines(idx, title, lead, items):
    blocks = [("title", f"Page {idx}: {title}"), ("body", f"Page purpose: {lead}")]
    for item in items:
        blocks.append(("bullet", item))
    for section in handoff_deepening_sections(title):
        blocks.append(("h2", section["heading"]))
        blocks.append(("body", section["body"]))
        for item in section["bullets"]:
            blocks.append(("bullet", item))
    blocks.append(("h2", "Completion goals"))
    blocks.append(("body", "A new worker can understand this page without chat history; the page gives concrete commands, files, or rules; and every named risk maps to the 25-page plan."))
    return blocks


def handoff_sources_to_lines(idx):
    blocks = [("title", f"Page {idx}: Research Sources Used")]
    for sid, name, url, proof in SOURCES:
        blocks.append(("body", f"{sid} - {name}: {url}. {proof}"))
    blocks.append(("h2", "Source-to-Workstream Usage Rules"))
    blocks.append(("body", "This appendix page exists so citations become actionable build rules. Future workers should use the links to decide what is technically possible, what must be measured, and what must be disclosed to users."))
    for item in SOURCE_APPENDIX_BULLETS:
        blocks.append(("bullet", item))
    blocks.append(("h2", "Verification Rule for Future Research"))
    blocks.append(("body", "Pricing, browser behavior, app-store rules, and mobile OS capabilities can change. Before shipping, submitting, pricing, or marketing the app, the responsible worker must reopen the relevant primary source, record the date checked, and update the issue."))
    for item in SOURCE_APPENDIX_VERIFICATION_BULLETS:
        blocks.append(("bullet", item))
    blocks.append(("h2", "Issue Conversion Rules"))
    blocks.append(("body", "The source appendix is complete only when it becomes work. The first GitHub migration should convert these source constraints into concrete issues so nobody has to rediscover the same limits during launch pressure."))
    for item in SOURCE_APPENDIX_ISSUE_BULLETS:
        blocks.append(("bullet", item))
    return blocks


def render_page(blocks, page_no, total, out_path, doc_title):
    img = Image.new("RGB", (1020, 1320), "#fbfbf8")
    draw = ImageDraw.Draw(img)
    draw.rectangle((0, 0, 1020, 56), fill="#0B2545")
    draw.text((55, 17), doc_title, font=F_SMALL, fill="white")
    draw.text((850, 17), f"Page {page_no} of {total}", font=F_SMALL, fill="white")
    columns = [(44, 76, 286), (368, 76, 286), (692, 76, 286)]
    col = 0
    x, y, width = columns[col]
    for kind, text in blocks:
        if y > 1210:
            if col < len(columns) - 1:
                col += 1
                x, y, width = columns[col]
            else:
                draw.text((x, y), "Overflow: expand this page before final issue conversion.", font=F_FOOT, fill="#9B1C1C")
                break
        if kind == "title":
            y = draw_wrapped(draw, x, y, text, F_TITLE, width, fill=(11, 37, 69), line_gap=2)
            y += 4
        elif kind == "h2":
            draw.rectangle((x - 4, y - 2, x + width, y + 15), fill="#E8EEF5")
            y = draw_wrapped(draw, x, y, text, F_H2, width, fill=(31, 77, 120), line_gap=1)
            y += 2
        elif kind == "bullet":
            y = draw_wrapped(draw, x + 7, y, text, F_BODY, width - 7, line_gap=1, bullet=True)
            y += 1
        else:
            y = draw_wrapped(draw, x, y, text, F_BODY, width, line_gap=1)
            y += 2
    draw.line((55, 1268, 965, 1268), fill="#DADCE0", width=1)
    draw.text((55, 1284), "Remote Controller product planning artifact - preview generated from the same structured content as the DOCX/PDF.", font=F_FOOT, fill="#596675")
    img.save(out_path)
    return y


def density(path):
    img = Image.open(path).convert("RGB")
    px = img.load()
    non_bg = 0
    total = img.width * img.height
    for yy in range(img.height):
        for xx in range(img.width):
            r, g, b = px[xx, yy]
            if (r, g, b) != (251, 251, 248):
                non_bg += 1
    return non_bg / total


def main():
    plan_dir = OUT / "page_previews_plan_verified"
    handoff_dir = OUT / "page_previews_handoff_verified"
    plan_dir.mkdir(exist_ok=True)
    handoff_dir.mkdir(exist_ok=True)
    plan_densities = []
    pages = expand_plan_pages()
    for page in pages:
        out = plan_dir / f"page-{page['number']:02d}.png"
        render_page(plan_page_to_lines(page), page["number"], 25, out, "25-page product execution plan")
        plan_densities.append((page["number"], density(out)))
    handoff_densities = []
    total_handoff = len(HANDOFF_PAGES) + 1
    for idx, (title, lead, items) in enumerate(HANDOFF_PAGES, start=1):
        out = handoff_dir / f"page-{idx:02d}.png"
        render_page(handoff_page_to_lines(idx, title, lead, items), idx, total_handoff, out, "handoff and transfer manual")
        handoff_densities.append((idx, density(out)))
    source_idx = total_handoff
    source_out = handoff_dir / f"page-{source_idx:02d}.png"
    render_page(handoff_sources_to_lines(source_idx), source_idx, total_handoff, source_out, "handoff and transfer manual")
    handoff_densities.append((source_idx, density(source_out)))
    report = OUT / "preview_density_audit.txt"
    report.write_text(
        "Plan preview page count: 25\n"
        + "\n".join(f"plan page {n:02d}: non-background density {d:.3f}" for n, d in plan_densities)
        + f"\n\nHandoff preview page count: {total_handoff}\n"
        + "\n".join(f"handoff page {n:02d}: non-background density {d:.3f}" for n, d in handoff_densities),
        encoding="utf-8",
    )
    print(report)


if __name__ == "__main__":
    main()
