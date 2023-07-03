{ writers }: input:

# Return the proper response to 'git rev-parse [--short=length] HEAD'. ArduPilot
# alternatively supports the GIT_VERSION, GIT_VERSION_INT and
# CHIBIOS_GIT_VERSION variables, but still requires a successful Git execution
# (see [1]), so we might as well implement this script rather than use the
# variables.
#
# [1] https://github.com/ArduPilot/ardupilot/pull/22848
writers.writePython3Bin "git" {} ''
  import argparse
  import os
  import sys


  def main() -> int:
      parser = argparse.ArgumentParser(prog="git")
      subparsers = parser.add_subparsers(title="subcommands")

      parser_rev_parse = subparsers.add_parser("rev-parse")
      parser_rev_parse.add_argument("rev", nargs="?")
      parser_rev_parse.add_argument("--short", metavar="length", type=int)
      parser_rev_parse.set_defaults(func=rev_parse)

      # PWD is the source root, not the best variable but the only one that is
      # exported
      path = os.path.relpath(os.getcwd(), os.environ["PWD"])

      args = parser.parse_args()
      if hasattr(args, "func"):
          return args.func(path, args)
      else:
          return 1


  def rev_parse(path: str, args: argparse.Namespace) -> int:
      if not args.rev:
          return 0
      if args.rev != "HEAD":
          print(f"error: unsupported revision: {args.rev}", file=sys.stderr)
          return 1

      # Only the root repo rev is known
      if path == ".":
          rev = "${input.rev}"
          if args.short:
              rev = rev[: args.short]
      else:
          rev = "<unknown>"
      print(rev)
      return 0


  if __name__ == "__main__":
      sys.exit(main())
''
