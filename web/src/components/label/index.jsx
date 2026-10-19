// Port JS từ material-kit-react: components/label (viên trạng thái soft/filled/outlined/inverted).
import { styled, alpha } from "@mui/material/styles";

const LabelRoot = styled("span", {
  shouldForwardProp: (prop) => !["color", "variant", "disabled", "sx"].includes(prop),
})(({ color, variant, disabled, theme }) => {
  const p = theme.palette;
  const def = color === "default" && {
    ...(variant === "filled" && { color: p.common.white, backgroundColor: p.text.primary }),
    ...(variant === "outlined" && { backgroundColor: "transparent", color: p.text.primary, border: `2px solid ${p.text.primary}` }),
    ...(variant === "soft" && { color: p.text.secondary, backgroundColor: alpha(p.grey[500], 0.16) }),
    ...(variant === "inverted" && { color: p.grey[800], backgroundColor: p.grey[300] }),
  };
  const col = color && color !== "default" && {
    ...(variant === "filled" && { color: p[color].contrastText, backgroundColor: p[color].main }),
    ...(variant === "outlined" && { backgroundColor: "transparent", color: p[color].main, border: `2px solid ${p[color].main}` }),
    ...(variant === "soft" && { color: p[color].dark, backgroundColor: alpha(p[color].main, 0.16) }),
    ...(variant === "inverted" && { color: p[color].darker, backgroundColor: p[color].lighter }),
  };
  return {
    height: 24, minWidth: 24, lineHeight: 0, flexShrink: 0, cursor: "default", alignItems: "center",
    whiteSpace: "nowrap", display: "inline-flex", gap: theme.spacing(0.75), justifyContent: "center",
    padding: theme.spacing(0, 0.75), fontSize: theme.typography.pxToRem(12),
    fontWeight: theme.typography.fontWeightBold, borderRadius: theme.shape.borderRadius * 0.75,
    transition: theme.transitions.create(["all"], { duration: theme.transitions.duration.shorter }),
    ...def, ...col,
    ...(disabled && { opacity: 0.48, pointerEvents: "none" }),
  };
});

const LabelIcon = styled("span")({
  width: 16, height: 16, flexShrink: 0,
  "& svg, img": { width: "100%", height: "100%", objectFit: "cover" },
});

const upperFirst = (s) => s.charAt(0).toUpperCase() + s.slice(1);

export function Label({ sx, endIcon, children, startIcon, className, disabled, variant = "soft", color = "default", ...other }) {
  return (
    <LabelRoot color={color} variant={variant} disabled={disabled} sx={sx}
      className={["mnl-label__root", className].filter(Boolean).join(" ")} {...other}>
      {startIcon && <LabelIcon>{startIcon}</LabelIcon>}
      {typeof children === "string" ? upperFirst(children) : children}
      {endIcon && <LabelIcon>{endIcon}</LabelIcon>}
    </LabelRoot>
  );
}
