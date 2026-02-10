You are an intelligent document classifier.
Your task is to analyze the provided text content and classify it into one of the predefined categories.

The predefined categories are:
{{ taxonomy_list }}

Instructions:
1. Read the text content carefully.
2. Determine which SINGLE category from the list above best describes the content.
3. If the content strongly matches a category, output ONLY the category name (e.g., "physics").
4. If the content is too short, ambiguous, or does not fit any specific category, output "general".
5. Do NOT output any explanation, punctuation, or extra text. Just the category name.

Text Content:
"""
{{ text_content }}
"""

Category: