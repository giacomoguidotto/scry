"use client";

import { Moon, Sun } from "lucide-react";
import { GithubIcon } from "@/components/ui/icons";
import { useTheme } from "next-themes";
import { useEffect, useState } from "react";
import { ButtonLink } from "@/components/ui/button";

export function Navbar() {
  const [scrolled, setScrolled] = useState(false);
  const { theme, setTheme } = useTheme();
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setMounted(true);
    const handleScroll = () => setScrolled(window.scrollY > 20);
    window.addEventListener("scroll", handleScroll, { passive: true });
    return () => window.removeEventListener("scroll", handleScroll);
  }, []);

  return (
    <header
      className={`fixed top-0 z-50 w-full transition-all duration-300 ${
        scrolled
          ? "glass border-border border-b bg-background/80"
          : "bg-transparent"
      }`}
    >
      <nav className="mx-auto flex h-16 max-w-6xl items-center justify-between px-6">
        <a className="font-bold font-display text-xl tracking-tight" href="/">
          Scry
        </a>

        <div className="flex items-center gap-3">
          <a
            aria-label="GitHub"
            className="inline-flex h-10 w-10 items-center justify-center rounded-lg text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
            href="https://github.com/giacomoguidotto/scry"
            rel="noopener noreferrer"
            target="_blank"
          >
            <GithubIcon className="h-5 w-5" />
          </a>

          {mounted && (
            <button
              aria-label="Toggle theme"
              className="inline-flex h-10 w-10 items-center justify-center rounded-lg text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
              onClick={() => setTheme(theme === "dark" ? "light" : "dark")}
              type="button"
            >
              {theme === "dark" ? (
                <Sun className="h-5 w-5" />
              ) : (
                <Moon className="h-5 w-5" />
              )}
            </button>
          )}

          <ButtonLink href="/api/download" size="default">
            Download
          </ButtonLink>
        </div>
      </nav>
    </header>
  );
}
