"use strict";

const os = require("node:os");

const TAILSCALE_IPV4_RE = /^100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\./;
const TAILSCALE_IPV6_PREFIX = "fd7a:115c:a1e0:";

function isTailscaleIPv4(address) {
  return TAILSCALE_IPV4_RE.test(address);
}

function isTailscaleIPv6(address) {
  const normalized = normalizeRemoteAddress(address).toLowerCase();
  return normalized.startsWith(TAILSCALE_IPV6_PREFIX);
}

function isPrivateIPv4(address) {
  return (
    address.startsWith("10.") ||
    address.startsWith("192.168.") ||
    /^172\.(1[6-9]|2\d|3[0-1])\./.test(address) ||
    isTailscaleIPv4(address)
  );
}

function normalizeRemoteAddress(address = "") {
  let value = String(address || "").trim().toLowerCase();
  if (value.startsWith("[") && value.includes("]")) value = value.slice(1, value.indexOf("]"));
  const scopeIndex = value.indexOf("%");
  if (scopeIndex !== -1) value = value.slice(0, scopeIndex);
  if (value.startsWith("::ffff:")) return value.slice(7);
  if (value === "::1") return "127.0.0.1";
  return value;
}

function isLoopbackAddress(address) {
  const normalized = normalizeRemoteAddress(address);
  return normalized === "127.0.0.1" || normalized === "localhost";
}

function isAllowedRemoteAddress(address, { allowPublic = false } = {}) {
  const normalized = normalizeRemoteAddress(address);
  if (isLoopbackAddress(normalized)) return true;
  if (/^\d+\.\d+\.\d+\.\d+$/.test(normalized) && isPrivateIPv4(normalized)) return true;
  if (isTailscaleIPv6(normalized)) return true;
  return Boolean(allowPublic);
}

function classifyAddress(address) {
  address = normalizeRemoteAddress(address);
  if (isTailscaleIPv4(address) || isTailscaleIPv6(address)) return "tailscale";
  if (address.startsWith("192.168.") || address.startsWith("10.") || /^172\.(1[6-9]|2\d|3[0-1])\./.test(address)) {
    return "lan";
  }
  return "other";
}

function getNetworkRisk(addresses = []) {
  const hasTunnel = addresses.some((address) => address.kind === "tunnel" || address.kind === "other");
  const hasTailscale = addresses.some((address) => address.kind === "tailscale");
  if (hasTunnel) {
    return {
      level: "public-tunnel",
      requiresFreshApproval: true,
      message: "Public tunnel mode is higher risk. Use only for short tests with fresh approval."
    };
  }
  if (hasTailscale) {
    return {
      level: "tailscale",
      requiresFreshApproval: true,
      message: "Tailscale private network detected. Keep approval active for each phone."
    };
  }
  return {
    level: "lan",
    requiresFreshApproval: true,
    message: "LAN mode. Same-Wi-Fi or private VPN addresses only."
  };
}

function firstAddress(addresses, kind) {
  return addresses.find((address) => address.kind === kind);
}

function getNetworkValidation(addresses = []) {
  const lan = firstAddress(addresses, "lan");
  const tailscale = firstAddress(addresses, "tailscale");
  const tunnel = firstAddress(addresses, "tunnel");
  return {
    sameWifi: {
      status: lan ? "ready" : "missing",
      label: "Same Wi-Fi",
      url: lan?.url || "",
      detail: lan
        ? `Scan the LAN QR from the phone while it is on the same Wi-Fi as ${lan.name}.`
        : "No private LAN address is available. Connect the laptop to Wi-Fi or Ethernet, then refresh.",
      checks: [
        "Phone and laptop are on the same local network.",
        "Scan the LAN QR code from the host console.",
        "Pair with the current PIN and approve on the laptop."
      ]
    },
    tailscale: {
      status: tailscale ? "ready" : "missing",
      label: "Different Wi-Fi",
      url: tailscale?.url || "",
      detail: tailscale
        ? `Use the Tailscale QR or URL from ${tailscale.name} when the phone is away from this Wi-Fi.`
        : "No Tailscale IPv4 100.64.0.0/10 or IPv6 fd7a:115c:a1e0::/48 address is detected. Start Tailscale on laptop and phone, then refresh.",
      checks: [
        "Laptop and phone are signed into the same Tailscale tailnet.",
        "The host console shows a Tailscale address.",
        "Open the Tailscale URL from cellular or another Wi-Fi, then approve on the laptop."
      ]
    },
    tunnel: {
      status: tunnel ? "testing-only" : "off",
      label: "Public tunnel",
      url: tunnel?.url || "",
      detail: tunnel
        ? "Temporary public tunnel is advertised. Use only for short tests with fresh approval."
        : "Public tunnel is off, which is the safer default for a full-laptop controller.",
      checks: [
        "Use only after PIN, approval, timeout, and kill switch checks pass.",
        "Keep the tunnel short-lived.",
        "Turn it off when the test is finished."
      ]
    }
  };
}

function isUsableNetworkFamily(family) {
  return family === "IPv4" || family === 4 || family === "IPv6" || family === 6;
}

function formatAddressUrl(address, port) {
  const normalized = normalizeRemoteAddress(address);
  if (normalized.includes(":")) return `http://[${normalized}]:${port}`;
  return `http://${normalized}:${port}`;
}

function getReachableAddresses(port, options = {}) {
  const addresses = [];
  for (const [name, entries] of Object.entries(os.networkInterfaces())) {
    for (const entry of entries || []) {
      if (!isUsableNetworkFamily(entry.family) || entry.internal) continue;
      const address = normalizeRemoteAddress(entry.address);
      const isPrivateV4 = /^\d+\.\d+\.\d+\.\d+$/.test(address) && isPrivateIPv4(address);
      const isTailnetV6 = address.includes(":") && isTailscaleIPv6(address);
      if (!isPrivateV4 && !isTailnetV6) continue;
      addresses.push({
        name,
        address,
        url: formatAddressUrl(address, port),
        kind: classifyAddress(address)
      });
    }
  }
  if (options.publicUrl) {
    addresses.push({
      name: "Public tunnel",
      address: options.publicUrl,
      url: options.publicUrl,
      kind: "tunnel"
    });
  }
  return addresses.sort((a, b) => a.kind.localeCompare(b.kind) || a.name.localeCompare(b.name));
}

module.exports = {
  classifyAddress,
  formatAddressUrl,
  getNetworkRisk,
  getNetworkValidation,
  getReachableAddresses,
  isAllowedRemoteAddress,
  isLoopbackAddress,
  isPrivateIPv4,
  isTailscaleIPv4,
  isTailscaleIPv6,
  normalizeRemoteAddress
};
