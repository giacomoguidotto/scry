"use client";

import { GithubIcon } from "@/components/ui/icons";
import { motion } from "motion/react";
import { ButtonLink } from "@/components/ui/button";
import { scaleIn } from "@/lib/motion";

export function OpenSource() {
  return (
    <section className="px-6 py-24 md:py-32">
      <motion.div
        className="glass mx-auto max-w-4xl rounded-2xl border border-border bg-card/60 p-12 text-center md:p-16"
        initial="hidden"
        variants={scaleIn}
        viewport={{ once: true, margin: "-100px" }}
        whileInView="show"
      >
        <h2>Built in the open</h2>
        <p className="mt-4 text-lg text-muted-foreground">
          Scry is MIT-licensed and open source. Contributions welcome.
        </p>
        <div className="mt-8">
          <ButtonLink
            href="https://github.com/giacomoguidotto/scry"
            rel="noopener noreferrer"
            size="lg"
            target="_blank"
            variant="secondary"
          >
            <GithubIcon className="h-5 w-5" />
            Star on GitHub
          </ButtonLink>
        </div>
      </motion.div>
    </section>
  );
}
