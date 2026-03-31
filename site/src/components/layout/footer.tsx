import { GithubIcon } from "@/components/ui/icons";

export function Footer() {
  return (
    <footer className="border-border border-t">
      <div className="mx-auto flex max-w-6xl items-center justify-between px-6 py-8">
        <div className="flex items-center gap-4">
          <span className="font-bold font-display text-lg">Scry</span>
          <span className="text-muted-foreground text-sm">MIT License</span>
        </div>

        <div className="flex items-center gap-4">
          <span className="text-muted-foreground text-sm">Made with &lt;3 by Giacomo</span>
          <a
            aria-label="GitHub"
            className="text-muted-foreground transition-colors hover:text-foreground"
            href="https://github.com/giacomoguidotto/scry"
            rel="noopener noreferrer"
            target="_blank"
          >
            <GithubIcon className="h-5 w-5" />
          </a>
        </div>
      </div>
    </footer>
  );
}
