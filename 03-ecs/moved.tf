# moved blocks tell Terraform that a resource was renamed in code.
# Without this, Terraform would destroy the old listener and create a
# new one on the same port — failing with a port conflict. With it,
# Terraform updates the existing listener in-place (changing the default
# action from "forward" to "redirect") and tracks it under the new name.
moved {
  from = aws_lb_listener.resumescorer
  to   = aws_lb_listener.resumescorer_http
}
