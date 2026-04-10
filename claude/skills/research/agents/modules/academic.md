# Academic Paper Search Strategy

## arXiv API
Use the arXiv API for academic papers:
```
http://export.arxiv.org/api/query?search_query=all:{topic}&max_results=5&sortBy=submittedDate&sortOrder=descending
```

## Query Tips
- Use academic terminology and formal language
- Include algorithm names, mathematical concepts
- Try specific technical terms: "transformer architecture", "gradient descent"
- Include category prefixes: "cs.AI", "cs.LG", "stat.ML"
- Search by author if known: "author:Hinton"

## Response Parsing
arXiv API returns Atom XML with entries containing:
- `title`: Paper title
- `summary`: Abstract
- `published`: Publication date
- `updated`: Last update date
- `id`: arXiv URL
- `author`: Author information
- `category`: Subject classification

## What to Extract
- **Theoretical Foundations**: Core concepts and mathematical principles
- **State of the Art**: Latest research developments
- **Performance Metrics**: Benchmark results and comparisons
- **Limitations**: Known issues and future work
- **Implementation Details**: Algorithmic approaches
- **Related Work**: References to other relevant papers

## When to Use Academic Module
- Cutting-edge AI/ML topics
- Theoretical computer science questions
- Mathematical algorithms and proofs
- Research-heavy topics requiring scholarly sources
- When recent academic developments are crucial

## Alternative Sources
If arXiv doesn't yield results:
- Google Scholar (via web search with site:scholar.google.com)
- IEEE Xplore (for engineering papers)
- ACM Digital Library (for CS papers)
- Specific conference proceedings (NeurIPS, ICML, etc.)