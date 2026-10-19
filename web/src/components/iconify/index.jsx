// Port JS từ material-kit-react: components/iconify (offline icon set, không tải icon qua mạng).
import { useId } from "react";
import { Icon, addCollection } from "@iconify/react";
import { styled } from "@mui/material/styles";
import allIcons from "./icon-sets.js";

let registered = false;
function registerIcons() {
  if (registered) return;
  const sets = {};
  Object.entries(allIcons).forEach(([key, value]) => {
    const [prefix, name] = key.split(":");
    (sets[prefix] ||= { prefix, icons: {}, width: 24, height: 24 }).icons[name] = value;
  });
  Object.values(sets).forEach((s) => addCollection(s));
  registered = true;
}

const IconRoot = styled(Icon)``;

export function Iconify({ className, icon, width = 20, height, sx, ...other }) {
  const id = useId();
  registerIcons();
  return (
    <IconRoot ssr id={id} icon={icon} className={["mnl-iconify__root", className].filter(Boolean).join(" ")}
      sx={[{ width, flexShrink: 0, height: height ?? width, display: "inline-flex" }, ...(Array.isArray(sx) ? sx : [sx])]}
      {...other} />
  );
}
