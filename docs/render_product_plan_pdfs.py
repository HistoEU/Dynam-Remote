from pathlib import Path
from reportlab.lib import colors
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import inch
from reportlab.platypus import Paragraph, Frame, Spacer, Table, TableStyle
from reportlab.pdfgen import canvas

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


PAGE_W, PAGE_H = letter


def styles():
    base = getSampleStyleSheet()
    base.add(ParagraphStyle(
        "TinyBody",
        parent=base["BodyText"],
        fontName="Helvetica",
        fontSize=5.25,
        leading=5.9,
        spaceAfter=1.15,
    ))
    base.add(ParagraphStyle(
        "TinyBullet",
        parent=base["TinyBody"],
        leftIndent=9,
        firstLineIndent=-5.5,
        bulletIndent=1.5,
    ))
    base.add(ParagraphStyle(
        "PageTitle",
        parent=base["Heading1"],
        fontName="Helvetica-Bold",
        fontSize=8.8,
        leading=9.6,
        textColor=colors.HexColor("#0B2545"),
        spaceAfter=2.2,
    ))
    base.add(ParagraphStyle(
        "SectionTitle",
        parent=base["Heading2"],
        fontName="Helvetica-Bold",
        fontSize=6.25,
        leading=6.8,
        textColor=colors.HexColor("#1F4D78"),
        spaceBefore=1.1,
        spaceAfter=1.1,
    ))
    base.add(ParagraphStyle(
        "Footer",
        parent=base["TinyBody"],
        fontSize=5.5,
        leading=6.0,
        textColor=colors.HexColor("#596675"),
    ))
    return base


STY = styles()


def draw_chrome(c, title, page_no, total):
    c.setFillColor(colors.HexColor("#0B2545"))
    c.rect(0, PAGE_H - 0.32 * inch, PAGE_W, 0.32 * inch, fill=1, stroke=0)
    c.setFillColor(colors.white)
    c.setFont("Helvetica-Bold", 7.5)
    c.drawString(0.55 * inch, PAGE_H - 0.205 * inch, title)
    c.setFont("Helvetica", 7.2)
    c.drawRightString(PAGE_W - 0.55 * inch, PAGE_H - 0.205 * inch, f"Page {page_no} of {total}")
    c.setStrokeColor(colors.HexColor("#DADCE0"))
    c.line(0.55 * inch, 0.42 * inch, PAGE_W - 0.55 * inch, 0.42 * inch)
    c.setFillColor(colors.HexColor("#596675"))
    c.setFont("Helvetica", 6.5)
    c.drawString(0.55 * inch, 0.25 * inch, "Remote Controller product planning artifact")


def story_for_plan_page(page):
    story = [
        Paragraph(f"Page {page['number']}: {page['title']}", STY["PageTitle"]),
        Paragraph(f"<b>Purpose:</b> {page['lead']}", STY["TinyBody"]),
    ]
    for section in page["sections"]:
        story.append(Paragraph(section["heading"], STY["SectionTitle"]))
        story.append(Paragraph(section["body"], STY["TinyBody"]))
        for item in section["bullets"]:
            story.append(Paragraph(item, STY["TinyBullet"], bulletText="•"))
    for section in execution_deepening_sections(page):
        story.append(Paragraph(section["heading"], STY["SectionTitle"]))
        story.append(Paragraph(section["body"], STY["TinyBody"]))
        for item in section["bullets"]:
            story.append(Paragraph(item, STY["TinyBullet"], bulletText="•"))
    data = [["Completion goals for this page"]] + [[g] for g in page["goals"]]
    table = Table(data, colWidths=[7.0 * inch])
    table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#E8EEF5")),
        ("TEXTCOLOR", (0, 0), (-1, 0), colors.HexColor("#0B2545")),
        ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
        ("FONTSIZE", (0, 0), (-1, -1), 5.7),
        ("LEADING", (0, 0), (-1, -1), 6.2),
        ("BOX", (0, 0), (-1, -1), 0.35, colors.HexColor("#AEB9C7")),
        ("INNERGRID", (0, 0), (-1, -1), 0.2, colors.HexColor("#DADCE0")),
        ("LEFTPADDING", (0, 0), (-1, -1), 4),
        ("RIGHTPADDING", (0, 0), (-1, -1), 4),
        ("TOPPADDING", (0, 0), (-1, -1), 1.2),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 1.2),
    ]))
    story.append(Spacer(1, 3))
    story.append(table)
    return story


def draw_story_page(c, story, title, page_no, total):
    draw_chrome(c, title, page_no, total)
    left_story = story
    frames = [
        Frame(0.42 * inch, 0.45 * inch, 3.55 * inch, PAGE_H - 0.82 * inch, showBoundary=0),
        Frame(4.08 * inch, 0.45 * inch, 3.98 * inch, PAGE_H - 0.82 * inch, showBoundary=0),
    ]
    for frame in frames:
        if left_story:
            frame.addFromList(left_story, c)
    if left_story:
        c.setFillColor(colors.HexColor("#9B1C1C"))
        c.setFont("Helvetica-Bold", 6)
        c.drawString(3.85 * inch, 0.46 * inch, "Overflow detected: expand this page before final issue conversion.")
    c.showPage()


def create_plan_pdf():
    path = OUT / "Remote_Controller_Product_Execution_Plan_25_Pages.pdf"
    c = canvas.Canvas(str(path), pagesize=letter)
    pages = expand_plan_pages()
    for page in pages:
        draw_story_page(c, story_for_plan_page(page), "25-page product execution plan", page["number"], 25)
    c.save()
    return path


def story_for_handoff_page(idx, title, lead, items):
    story = [
        Paragraph(f"Page {idx}: {title}", STY["PageTitle"]),
        Paragraph(f"<b>Page purpose:</b> {lead}", STY["TinyBody"]),
    ]
    for item in items:
        story.append(Paragraph(item, STY["TinyBullet"], bulletText="•"))
    for section in handoff_deepening_sections(title):
        story.append(Paragraph(section["heading"], STY["SectionTitle"]))
        story.append(Paragraph(section["body"], STY["TinyBody"]))
        for item in section["bullets"]:
            story.append(Paragraph(item, STY["TinyBullet"], bulletText="•"))
    story.append(Spacer(1, 5))
    story.append(Paragraph("<b>Completion goals:</b> a new worker can understand the page without chat history; the page gives concrete commands, files, or rules; and every named risk maps to the 25-page plan.", STY["TinyBody"]))
    return story


def create_handoff_pdf():
    path = OUT / "Remote_Controller_Handoff_and_Transfer_Manual.pdf"
    c = canvas.Canvas(str(path), pagesize=letter)
    total = len(HANDOFF_PAGES) + 1
    for idx, (title, lead, items) in enumerate(HANDOFF_PAGES, start=1):
        draw_story_page(c, story_for_handoff_page(idx, title, lead, items), "handoff and transfer manual", idx, total)
    story = [Paragraph("Research Sources Used", STY["PageTitle"])]
    for sid, name, url, proof in SOURCES:
        story.append(Paragraph(f"<b>{sid} - {name}</b>: {url}<br/>{proof}", STY["TinyBody"]))
    story.append(Paragraph("Source-to-Workstream Usage Rules", STY["SectionTitle"]))
    story.append(Paragraph("This appendix page exists so citations become actionable build rules. Future workers should use the links to decide what is technically possible, what must be measured, and what must be disclosed to users.", STY["TinyBody"]))
    for item in SOURCE_APPENDIX_BULLETS:
        story.append(Paragraph(item, STY["TinyBullet"], bulletText="â€¢"))
    story.append(Paragraph("Verification Rule for Future Research", STY["SectionTitle"]))
    story.append(Paragraph("Pricing, browser behavior, app-store rules, and mobile OS capabilities can change. Before shipping, submitting, pricing, or marketing the app, the responsible worker must reopen the relevant primary source, record the date checked, and update the issue.", STY["TinyBody"]))
    for item in SOURCE_APPENDIX_VERIFICATION_BULLETS:
        story.append(Paragraph(item, STY["TinyBullet"], bulletText="â€¢"))
    story.append(Paragraph("Issue Conversion Rules", STY["SectionTitle"]))
    story.append(Paragraph("The source appendix is complete only when it becomes work. The first GitHub migration should convert these source constraints into concrete issues so nobody has to rediscover the same limits during launch pressure.", STY["TinyBody"]))
    for item in SOURCE_APPENDIX_ISSUE_BULLETS:
        story.append(Paragraph(item, STY["TinyBullet"], bulletText="â€¢"))
    draw_story_page(c, story, "handoff and transfer manual", total, total)
    c.save()
    return path


if __name__ == "__main__":
    print(create_handoff_pdf())
    print(create_plan_pdf())
