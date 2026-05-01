import Foundation

public enum ExtractionPrompts {
    public static func defaultPrompt(forPageCount count: Int) -> String {
        count > 1 ? multiPagePrompt : singlePagePrompt
    }

    public static let notesGuidance = """
    The reader may have scribbled handwritten notes in the page margins or
    between lines. Notes are HANDWRITTEN by the reader — cursive or block
    lettering, ink or graphite from a pen or pencil, with shaky or uneven
    strokes and a wandering baseline. They are visually distinct from the
    book's printed/typeset text. Do NOT confuse a handwritten note with the
    highlighted text itself: the highlighted text is part of the printed book
    body (just with a hand-applied mark over or around it), while the note
    is separate writing the reader added on top of the page. The text of a
    note must NEVER include any printed body text — only the handwriting.

    For each highlight, attach the handwritten note that is physically closest
    to it (same line, adjacent margin, or directly above/below) as the note
    field. If a note is not clearly associated with any single highlight, skip
    it. If a highlight has no nearby handwritten note, set note to null.
    Transcribe notes verbatim; if a note is illegible, use note: null rather
    than guessing. Printed text (footnotes, captions, headings, page numbers)
    is NEVER a note.
    """

    public static let singlePagePrompt = """
    You are extracting highlighted passages from a photograph of a book page.

    The page may contain zero, one, or multiple distinct passages physically marked
    by the reader with highlighter, pen, pencil, brackets, or underline. Return
    every distinct passage you find as a separate entry in the highlights array,
    in reading order (top to bottom, then left to right).

    Only return passages that show a hand-applied mark. Ignore typographic emphasis
    that is part of the printed book itself — italics, bold, small caps, drop caps,
    pull quotes, chapter epigraphs, captions, and headings are NOT highlights unless
    the reader has additionally marked them by hand. A hand-applied mark looks like
    an irregular ink/graphite stroke, a translucent highlighter overlay, a margin
    bracket, or an underline drawn by hand (often slightly crooked or extending
    beyond the text baseline). When in doubt, treat the text as unmarked.

    \(notesGuidance)

    For each passage:
    - Include only the marked text. Do not include surrounding unmarked text.
      Even if the marked region begins or ends mid-sentence, mid-clause, or
      mid-word, return exactly what is marked — do NOT extend the passage to
      complete a sentence, clause, thought, or word. If the reader chose to
      highlight a fragment, the fragment is the answer.
    - Preserve original punctuation verbatim. Do not add quotation marks or emphasis
      markers (e.g. asterisks, underscores) for printed italics or bold.
    - Treat line wraps as single spaces — do not include hyphenation artifacts.
    - If a page number is clearly visible and unambiguous, return it as an integer
      in page_number. Otherwise return null.
    - Attach the closest handwritten margin note as the note field, or null.

    If two marks are clearly part of the same continuous sentence or paragraph,
    treat them as a single passage. If they are separated by unmarked text or are
    on different lines/paragraphs, treat them as separate passages.

    If no highlight is detected, return an empty highlights array.
    """

    public static let multiPagePrompt = """
    You are extracting highlighted passages from photographs of consecutive book
    pages.

    The images are provided in reading order: the first image is the first page,
    and each subsequent image is the page that immediately follows. Process them
    in that order.

    A page may contain zero, one, or multiple distinct passages physically marked
    by the reader with highlighter, pen, pencil, brackets, or underline. Return
    every distinct passage you find as a separate entry in the highlights array,
    in reading order across all pages (top to bottom, then left to right, then
    next page).

    A single highlighted passage may continue from the bottom of one page to the
    top of the next page. When this happens, merge it into a single highlights
    entry — do not return two separate entries. Stitch the text across the page
    break naturally (collapse the page boundary into a single space, and resolve
    any hyphenation at the seam by joining the word parts without a hyphen). Set
    page_number to the page where the passage begins.

    Only return passages that show a hand-applied mark. Ignore typographic emphasis
    that is part of the printed book itself — italics, bold, small caps, drop caps,
    pull quotes, chapter epigraphs, captions, and headings are NOT highlights unless
    the reader has additionally marked them by hand. A hand-applied mark looks like
    an irregular ink/graphite stroke, a translucent highlighter overlay, a margin
    bracket, or an underline drawn by hand (often slightly crooked or extending
    beyond the text baseline). When in doubt, treat the text as unmarked.

    \(notesGuidance)

    For each passage:
    - Include only the marked text. Do not include surrounding unmarked text.
      Even if the marked region begins or ends mid-sentence, mid-clause, or
      mid-word, return exactly what is marked — do NOT extend the passage to
      complete a sentence, clause, thought, or word. If the reader chose to
      highlight a fragment, the fragment is the answer. (The exception is
      stitching a passage that wraps the page break, as described above.)
    - Preserve original punctuation verbatim. Do not add quotation marks or emphasis
      markers (e.g. asterisks, underscores) for printed italics or bold.
    - Treat line wraps as single spaces — do not include hyphenation artifacts.
    - If a page number is clearly visible and unambiguous, return it as an integer
      in page_number. Otherwise return null. The same page_number can repeat across
      passages on the same page.
    - Attach the closest handwritten margin note (on the same page as the
      highlight) as the note field, or null.

    If two marks on the same page are clearly part of the same continuous sentence
    or paragraph, treat them as a single passage. If they are separated by unmarked
    text or are on different lines/paragraphs, treat them as separate passages.

    If no highlight is detected on any page, return an empty highlights array.
    """
}
