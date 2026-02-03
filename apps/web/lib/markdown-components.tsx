"use client";

import { type ReactNode, type HTMLAttributes, type AnchorHTMLAttributes, type TableHTMLAttributes, type TdHTMLAttributes, type ThHTMLAttributes } from "react";
import { Check, Copy } from "lucide-react";
import { useState, useCallback, useRef, useEffect } from "react";

/**
 * ReactMarkdown passes AST-related props (node, siblingCount, index, etc.) to custom components.
 * These must NOT be spread to DOM elements or they create invalid HTML like <h2 node="[object Object]">
 * which breaks Tailwind's prose CSS selectors.
 *
 * This file provides sanitized component overrides for ReactMarkdown.
 */

// Props that ReactMarkdown passes which should NOT go to DOM elements
const REACT_MARKDOWN_INTERNAL_PROPS = new Set([
  "node",
  "siblingCount",
  "index",
  "ordered",
  "isHeader",
  "inline",
  "sourcePosition",
  "depth",
  "checked",
]);

/**
 * Strips ReactMarkdown internal props from an object, returning only DOM-safe props
 */
function sanitizeProps<T extends Record<string, unknown>>(props: T): Record<string, unknown> {
  const sanitized: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(props)) {
    if (!REACT_MARKDOWN_INTERNAL_PROPS.has(key)) {
      sanitized[key] = value;
    }
  }
  return sanitized;
}

// Common prop interface that ReactMarkdown passes
interface MarkdownProps {
  children?: ReactNode;
  className?: string;
  node?: unknown;
  [key: string]: unknown;
}

// Heading components - demoted by 1 level since page has its own h1
function H1({ children, ...props }: MarkdownProps) {
  const safeProps = sanitizeProps(props) as HTMLAttributes<HTMLHeadingElement>;
  return <h2 {...safeProps}>{children}</h2>;
}

function H2({ children, ...props }: MarkdownProps) {
  const safeProps = sanitizeProps(props) as HTMLAttributes<HTMLHeadingElement>;
  return <h3 {...safeProps}>{children}</h3>;
}

function H3({ children, ...props }: MarkdownProps) {
  const safeProps = sanitizeProps(props) as HTMLAttributes<HTMLHeadingElement>;
  return <h4 {...safeProps}>{children}</h4>;
}

function H4({ children, ...props }: MarkdownProps) {
  const safeProps = sanitizeProps(props) as HTMLAttributes<HTMLHeadingElement>;
  return <h5 {...safeProps}>{children}</h5>;
}

function H5({ children, ...props }: MarkdownProps) {
  const safeProps = sanitizeProps(props) as HTMLAttributes<HTMLHeadingElement>;
  return <h6 {...safeProps}>{children}</h6>;
}

function H6({ children, ...props }: MarkdownProps) {
  const safeProps = sanitizeProps(props) as HTMLAttributes<HTMLHeadingElement>;
  return <h6 {...safeProps}>{children}</h6>;
}

// Paragraph component
function Paragraph({ children, ...props }: MarkdownProps) {
  const safeProps = sanitizeProps(props) as HTMLAttributes<HTMLParagraphElement>;
  return <p {...safeProps}>{children}</p>;
}

// Anchor component with external link handling
interface AnchorProps extends MarkdownProps {
  href?: string;
}

function Anchor({ children, href, ...props }: AnchorProps) {
  const safeProps = sanitizeProps(props) as AnchorHTMLAttributes<HTMLAnchorElement>;
  const isExternal = href?.startsWith("http");

  return (
    <a
      href={href}
      {...safeProps}
      {...(isExternal ? { target: "_blank", rel: "noopener noreferrer" } : {})}
    >
      {children}
    </a>
  );
}

// List components
function UnorderedList({ children, ...props }: MarkdownProps) {
  const safeProps = sanitizeProps(props) as HTMLAttributes<HTMLUListElement>;
  return <ul {...safeProps}>{children}</ul>;
}

function OrderedList({ children, ...props }: MarkdownProps) {
  const safeProps = sanitizeProps(props) as HTMLAttributes<HTMLOListElement>;
  return <ol {...safeProps}>{children}</ol>;
}

function ListItem({ children, ...props }: MarkdownProps) {
  const safeProps = sanitizeProps(props) as HTMLAttributes<HTMLLIElement>;
  return <li {...safeProps}>{children}</li>;
}

// Blockquote component
function Blockquote({ children, ...props }: MarkdownProps) {
  const safeProps = sanitizeProps(props) as HTMLAttributes<HTMLQuoteElement>;
  return <blockquote {...safeProps}>{children}</blockquote>;
}

// Inline code component
function InlineCode({ children, ...props }: MarkdownProps) {
  const safeProps = sanitizeProps(props) as HTMLAttributes<HTMLElement>;
  return <code {...safeProps}>{children}</code>;
}

// Pre component - wrapper for code blocks with copy button
function Pre({ children, ...props }: MarkdownProps) {
  const safeProps = sanitizeProps(props) as HTMLAttributes<HTMLPreElement>;
  const [copied, setCopied] = useState(false);
  const timeoutRef = useRef<NodeJS.Timeout | null>(null);

  // Cleanup timeout on unmount
  useEffect(() => {
    return () => {
      if (timeoutRef.current) {
        clearTimeout(timeoutRef.current);
      }
    };
  }, []);

  const handleCopy = useCallback(async () => {
    // Extract text content from children
    const extractText = (node: ReactNode): string => {
      if (typeof node === "string") return node;
      if (typeof node === "number") return String(node);
      if (!node) return "";
      if (Array.isArray(node)) return node.map(extractText).join("");
      if (typeof node === "object" && "props" in node) {
        return extractText((node as { props: { children?: ReactNode } }).props.children);
      }
      return "";
    };

    const text = extractText(children);
    if (text) {
      try {
        await navigator.clipboard.writeText(text);
        setCopied(true);
        // Clear any existing timeout
        if (timeoutRef.current) {
          clearTimeout(timeoutRef.current);
        }
        timeoutRef.current = setTimeout(() => setCopied(false), 2000);
      } catch {
        // Clipboard API not available or permission denied - fail silently
        console.warn("Failed to copy to clipboard");
      }
    }
  }, [children]);

  return (
    <div className="group relative my-6">
      {/* Copy button */}
      <button
        onClick={handleCopy}
        className="absolute right-3 top-3 z-10 opacity-0 group-hover:opacity-100 group-focus-within:opacity-100 focus-visible:opacity-100 transition-opacity p-1.5 rounded-md bg-muted/80 hover:bg-muted text-muted-foreground hover:text-foreground focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background"
        aria-label="Copy code"
      >
        {copied ? (
          <Check className="h-3.5 w-3.5 text-[oklch(0.72_0.19_145)]" />
        ) : (
          <Copy className="h-3.5 w-3.5" />
        )}
      </button>
      <pre
        {...safeProps}
        className="rounded-xl border border-border/50 bg-muted/50 p-4 overflow-x-auto"
      >
        {children}
      </pre>
    </div>
  );
}

// Strong/bold component
function Strong({ children, ...props }: MarkdownProps) {
  const safeProps = sanitizeProps(props) as HTMLAttributes<HTMLElement>;
  return <strong {...safeProps}>{children}</strong>;
}

// Emphasis/italic component
function Em({ children, ...props }: MarkdownProps) {
  const safeProps = sanitizeProps(props) as HTMLAttributes<HTMLElement>;
  return <em {...safeProps}>{children}</em>;
}

// Horizontal rule
function Hr(props: MarkdownProps) {
  const safeProps = sanitizeProps(props) as HTMLAttributes<HTMLHRElement>;
  return <hr {...safeProps} className="my-8 border-border/50" />;
}

// Table components
function Table({ children, ...props }: MarkdownProps) {
  const safeProps = sanitizeProps(props) as TableHTMLAttributes<HTMLTableElement>;
  return (
    <div className="my-6 overflow-x-auto">
      <table {...safeProps} className="w-full border-collapse">
        {children}
      </table>
    </div>
  );
}

function TableHead({ children, ...props }: MarkdownProps) {
  const safeProps = sanitizeProps(props) as HTMLAttributes<HTMLTableSectionElement>;
  return <thead {...safeProps} className="bg-muted/50">{children}</thead>;
}

function TableBody({ children, ...props }: MarkdownProps) {
  const safeProps = sanitizeProps(props) as HTMLAttributes<HTMLTableSectionElement>;
  return <tbody {...safeProps}>{children}</tbody>;
}

function TableRow({ children, ...props }: MarkdownProps) {
  const safeProps = sanitizeProps(props) as HTMLAttributes<HTMLTableRowElement>;
  return <tr {...safeProps} className="border-b border-border/50">{children}</tr>;
}

function TableCell({ children, ...props }: MarkdownProps) {
  const safeProps = sanitizeProps(props) as TdHTMLAttributes<HTMLTableCellElement>;
  return <td {...safeProps} className="px-4 py-3 text-sm">{children}</td>;
}

function TableHeader({ children, ...props }: MarkdownProps) {
  const safeProps = sanitizeProps(props) as ThHTMLAttributes<HTMLTableCellElement>;
  return <th {...safeProps} className="px-4 py-3 text-left text-sm font-semibold">{children}</th>;
}

/**
 * Complete set of sanitized ReactMarkdown components
 * Use this with ReactMarkdown's `components` prop
 *
 * All components properly strip ReactMarkdown's internal props (node, siblingCount, etc.)
 * to prevent invalid HTML attributes that break Tailwind's prose CSS selectors.
 */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export const markdownComponents: Record<string, any> = {
  // Headings are demoted by 1 level (h1->h2, etc.) since page has its own h1
  h1: H1,
  h2: H2,
  h3: H3,
  h4: H4,
  h5: H5,
  h6: H6,

  // Text elements
  p: Paragraph,
  a: Anchor,
  strong: Strong,
  em: Em,

  // Lists
  ul: UnorderedList,
  ol: OrderedList,
  li: ListItem,

  // Code
  code: InlineCode,
  pre: Pre,

  // Other
  blockquote: Blockquote,
  hr: Hr,

  // Tables
  table: Table,
  thead: TableHead,
  tbody: TableBody,
  tr: TableRow,
  td: TableCell,
  th: TableHeader,
};
