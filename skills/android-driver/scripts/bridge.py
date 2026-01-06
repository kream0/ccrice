#!/usr/bin/env python3
"""
AgentBridge CLI - Bridge between AI agents and development environments.

This module provides the main CLI entry point for AgentBridge,
enabling AI agents to interact with various development tools and services.
"""

import base64
import json
import sys
import xml.etree.ElementTree as ET
from typing import Any

import click
import uiautomator2 as u2

# Global device variable for uiautomator2 connection
_device: u2.Device | None = None

# Global cache for the interactive element tree
_element_cache: dict[int, dict[str, Any]] = {}
_last_tree: list[dict[str, Any]] = []


def output_json_error(error: str, code: str = "ERROR") -> None:
    """Output an error message as JSON to stdout and exit with code 1.

    Args:
        error: The error message.
        code: Error code for categorization.
    """
    result = {
        "success": False,
        "error": error,
        "code": code,
    }
    click.echo(json.dumps(result))
    sys.exit(1)


def get_device() -> u2.Device:
    """Get the current device connection, auto-connecting if needed.

    Returns:
        The connected uiautomator2 Device instance.

    Raises:
        click.ClickException: If no device is connected and auto-connect fails.
    """
    global _device
    if _device is None:
        # Auto-connect to the first available device
        try:
            _device = u2.connect()
        except Exception as e:
            raise click.ClickException(
                f"No device connected and auto-connect failed: {e}"
            )
    return _device


def connect_device(device_id: str | None = None) -> u2.Device:
    """Connect to an Android device via uiautomator2.

    Args:
        device_id: Optional device serial/IP. If None, connects to the first available device.

    Returns:
        The connected uiautomator2 Device instance.

    Raises:
        click.ClickException: If connection fails.
    """
    global _device
    try:
        if device_id:
            _device = u2.connect(device_id)
        else:
            _device = u2.connect()
        return _device
    except Exception as e:
        raise click.ClickException(f"Failed to connect to device: {e}")


def _parse_bounds(bounds_str: str) -> dict[str, int] | None:
    """Parse Android bounds string '[x1,y1][x2,y2]' into a dictionary.

    Args:
        bounds_str: Bounds string in format '[x1,y1][x2,y2]'.

    Returns:
        Dictionary with x, y, width, height or None if parsing fails.
    """
    try:
        # Parse '[x1,y1][x2,y2]' format
        parts = bounds_str.replace("][", ",").strip("[]").split(",")
        if len(parts) == 4:
            x1, y1, x2, y2 = map(int, parts)
            return {"x": x1, "y": y1, "w": x2 - x1, "h": y2 - y1}
    except (ValueError, AttributeError):
        pass
    return None


def _is_interactive(element: ET.Element) -> bool:
    """Check if an element is interactive.

    An element is considered interactive if it is clickable, long-clickable,
    scrollable, focusable, or checkable.

    Args:
        element: XML element from UI hierarchy.

    Returns:
        True if the element is interactive.
    """
    return (
        element.get("clickable") == "true"
        or element.get("long-clickable") == "true"
        or element.get("scrollable") == "true"
        or element.get("focusable") == "true"
        or element.get("checkable") == "true"
    )


def _extract_element_info(element: ET.Element, element_id: int) -> dict[str, Any]:
    """Extract relevant information from an XML element.

    Args:
        element: XML element from UI hierarchy.
        element_id: Numeric ID to assign to this element.

    Returns:
        Dictionary containing compressed element information.
    """
    info: dict[str, Any] = {"id": element_id}

    # Class name (shortened to just the class, not full package)
    class_name = element.get("class", "")
    if "." in class_name:
        class_name = class_name.rsplit(".", 1)[-1]
    if class_name:
        info["cls"] = class_name

    # Text content
    text = element.get("text", "")
    if text:
        info["txt"] = text[:50]  # Truncate long text

    # Content description
    desc = element.get("content-desc", "")
    if desc:
        info["desc"] = desc[:50]

    # Resource ID (shortened)
    res_id = element.get("resource-id", "")
    if res_id:
        # Strip package prefix if present
        if ":id/" in res_id:
            res_id = res_id.split(":id/")[-1]
        info["res"] = res_id

    # Bounds
    bounds = _parse_bounds(element.get("bounds", ""))
    if bounds:
        info["bounds"] = bounds

    # Interactive flags (only include if true, as compressed format)
    flags = []
    if element.get("clickable") == "true":
        flags.append("C")  # Clickable
    if element.get("long-clickable") == "true":
        flags.append("L")  # Long-clickable
    if element.get("scrollable") == "true":
        flags.append("S")  # Scrollable
    if element.get("focusable") == "true":
        flags.append("F")  # Focusable
    if element.get("checkable") == "true":
        flags.append("K")  # Checkable
    if element.get("checked") == "true":
        flags.append("k")  # Checked (lowercase = state)
    if element.get("enabled") == "false":
        flags.append("D")  # Disabled
    if element.get("selected") == "true":
        flags.append("s")  # Selected
    if flags:
        info["flags"] = "".join(flags)

    return info


def get_interactive_tree(include_all: bool = False) -> list[dict[str, Any]]:
    """Parse UI hierarchy and extract interactive elements.

    Retrieves the current UI hierarchy from the connected device,
    parses the XML, filters for interactive elements, assigns numeric IDs,
    and caches the results for later reference.

    Args:
        include_all: If True, include all elements, not just interactive ones.

    Returns:
        List of dictionaries containing element information.

    Raises:
        click.ClickException: If no device is connected or parsing fails.
    """
    global _element_cache, _last_tree

    d = get_device()

    try:
        # Get UI hierarchy XML
        xml_content = d.dump_hierarchy()

        # Parse XML
        root = ET.fromstring(xml_content)

        # Clear previous cache
        _element_cache.clear()
        elements: list[dict[str, Any]] = []
        element_id = 0

        # Traverse all elements in the hierarchy
        for element in root.iter():
            # Skip the root hierarchy node
            if element.tag == "hierarchy":
                continue

            # Filter for interactive elements unless include_all is set
            if not include_all and not _is_interactive(element):
                continue

            # Extract and store element info
            info = _extract_element_info(element, element_id)

            # Store full element data in cache for later interaction
            _element_cache[element_id] = {
                **info,
                "_element": element,  # Keep reference to original element
                "_bounds_raw": element.get("bounds", ""),
            }

            elements.append(info)
            element_id += 1

        _last_tree = elements
        return elements

    except ET.ParseError as e:
        raise click.ClickException(f"Failed to parse UI hierarchy: {e}")
    except Exception as e:
        raise click.ClickException(f"Failed to get UI hierarchy: {e}")


def get_element_by_id(element_id: int) -> dict[str, Any] | None:
    """Get a cached element by its numeric ID, auto-scanning if needed.

    Args:
        element_id: The numeric ID assigned during the last scan.

    Returns:
        The cached element dictionary or None if not found.
    """
    # Auto-scan if cache is empty
    if not _element_cache:
        get_interactive_tree()
    return _element_cache.get(element_id)


def get_element_center(element_id: int) -> tuple[int, int] | None:
    """Get the center coordinates of a cached element.

    Args:
        element_id: The numeric ID assigned during the last scan.

    Returns:
        Tuple of (x, y) center coordinates or None if element not found.
    """
    element = _element_cache.get(element_id)
    if element and "bounds" in element:
        bounds = element["bounds"]
        center_x = bounds["x"] + bounds["w"] // 2
        center_y = bounds["y"] + bounds["h"] // 2
        return (center_x, center_y)
    return None


@click.group()
@click.version_option(version="0.1.0", prog_name="agentbridge")
@click.option("--verbose", "-v", is_flag=True, help="Enable verbose output.")
@click.option("--config", "-c", type=click.Path(), help="Path to configuration file.")
@click.pass_context
def cli(ctx: click.Context, verbose: bool, config: str | None) -> None:
    """AgentBridge - Bridge between AI agents and development environments.

    Provides tools and commands for AI agents to interact with
    development workflows, version control, and other services.
    """
    # Ensure ctx.obj exists for storing shared state
    ctx.ensure_object(dict)
    ctx.obj["verbose"] = verbose
    ctx.obj["config"] = config


@cli.command()
@click.pass_context
def status(ctx: click.Context) -> None:
    """Show the current status of AgentBridge."""
    verbose = ctx.obj.get("verbose", False)
    click.echo("AgentBridge Status: Ready")
    if verbose:
        click.echo("Configuration: Default")
        click.echo("Connected services: None")


@cli.command()
@click.argument("device", required=False)
@click.pass_context
def connect(ctx: click.Context, device: str | None) -> None:
    """Connect to an Android device via uiautomator2.

    DEVICE: Optional device serial or IP address. If not provided,
    connects to the first available device.
    """
    verbose = ctx.obj.get("verbose", False)
    if verbose:
        if device:
            click.echo(f"Connecting to device: {device}")
        else:
            click.echo("Connecting to first available device...")

    try:
        d = connect_device(device)
        device_info = d.info
        click.echo(f"Connected to device: {device_info.get('serial', 'unknown')}")
        if verbose:
            click.echo(f"  Model: {device_info.get('productName', 'unknown')}")
            click.echo(f"  SDK: {device_info.get('sdkInt', 'unknown')}")
    except click.ClickException:
        raise
    except Exception as e:
        raise click.ClickException(f"Connection failed: {e}")


@cli.command()
@click.pass_context
def info(ctx: click.Context) -> None:
    """Display device information as JSON.

    Outputs device serial, screen size, and current app information.
    Requires an active device connection.
    """
    d = get_device()

    # Get device info
    device_info = d.info

    # Get screen size
    window_size = d.window_size()

    # Get current app info
    current_app = d.app_current()

    # Build output dictionary
    output: dict[str, Any] = {
        "serial": device_info.get("serial", "unknown"),
        "screen": {
            "width": window_size[0],
            "height": window_size[1],
        },
        "currentApp": {
            "package": current_app.get("package", "unknown"),
            "activity": current_app.get("activity", "unknown"),
        },
    }

    # Output as formatted JSON
    click.echo(json.dumps(output, indent=2))


@cli.command()
@click.argument("element_id", type=int)
@click.option("--long", "-l", "long_press", is_flag=True, help="Perform a long press instead of tap.")
@click.option("--duration", "-d", type=float, default=0.5, help="Duration for long press in seconds.")
@click.pass_context
def tap(ctx: click.Context, element_id: int, long_press: bool, duration: float) -> None:
    """Tap on an element by its numeric ID from the last scan.

    Looks up the element in the cache, calculates the center coordinates
    from its bounds, and performs a tap action on the device.

    ELEMENT_ID: The numeric ID of the element to tap (from scan output).

    Examples:
        agentbridge tap 5       # Tap element with ID 5
        agentbridge tap 3 -l    # Long press element with ID 3
    """
    verbose = ctx.obj.get("verbose", False)
    d = get_device()

    # Look up element in cache
    element = get_element_by_id(element_id)
    if element is None:
        output_json_error(
            f"Element {element_id} not found in cache. Run 'scan' first.",
            "ELEMENT_NOT_FOUND"
        )

    # Get center coordinates
    center = get_element_center(element_id)
    if center is None:
        output_json_error(
            f"Element {element_id} has no bounds information.",
            "NO_BOUNDS"
        )

    x, y = center

    if verbose:
        elem_desc = element.get("txt") or element.get("desc") or element.get("res") or element.get("cls", "unknown")
        click.echo(f"Tapping element {element_id} ({elem_desc}) at ({x}, {y})", err=True)

    try:
        if long_press:
            d.long_click(x, y, duration=duration)
            action = "long_press"
        else:
            d.click(x, y)
            action = "tap"

        # Output success as JSON
        result = {
            "action": action,
            "element_id": element_id,
            "x": x,
            "y": y,
            "success": True,
        }
        click.echo(json.dumps(result))

    except Exception as e:
        output_json_error(f"Tap failed: {e}", "TAP_FAILED")


@cli.command("type")
@click.argument("element_id", type=int)
@click.argument("text")
@click.option("--clear", "-c", is_flag=True, help="Clear existing text before typing.")
@click.option("--enter", "-e", is_flag=True, help="Press Enter after typing.")
@click.pass_context
def type_text(ctx: click.Context, element_id: int, text: str, clear: bool, enter: bool) -> None:
    """Type text into an element by its numeric ID from the last scan.

    Taps the element to focus it, optionally clears existing text,
    then sends the specified text. Can optionally press Enter after typing.

    ELEMENT_ID: The numeric ID of the element to type into (from scan output).
    TEXT: The text to type into the element.

    Examples:
        agentbridge type 5 "Hello World"           # Type into element 5
        agentbridge type 3 "search query" -e       # Type and press Enter
        agentbridge type 2 "new text" -c           # Clear and type
    """
    verbose = ctx.obj.get("verbose", False)
    d = get_device()

    # Look up element in cache
    element = get_element_by_id(element_id)
    if element is None:
        output_json_error(
            f"Element {element_id} not found in cache. Run 'scan' first.",
            "ELEMENT_NOT_FOUND"
        )

    # Get center coordinates
    center = get_element_center(element_id)
    if center is None:
        output_json_error(
            f"Element {element_id} has no bounds information.",
            "NO_BOUNDS"
        )

    x, y = center

    if verbose:
        elem_desc = element.get("txt") or element.get("desc") or element.get("res") or element.get("cls", "unknown")
        click.echo(f"Typing into element {element_id} ({elem_desc}) at ({x}, {y})", err=True)

    try:
        # Tap to focus the element
        d.click(x, y)

        # Clear existing text if requested
        if clear:
            d.clear_text()

        # Send the text
        d.send_keys(text)

        # Press Enter if requested
        if enter:
            d.press("enter")

        # Output success as JSON
        result = {
            "action": "type",
            "element_id": element_id,
            "text": text,
            "cleared": clear,
            "enter_pressed": enter,
            "success": True,
        }
        click.echo(json.dumps(result))

    except Exception as e:
        output_json_error(f"Type failed: {e}", "TYPE_FAILED")


@cli.command()
@click.argument("direction", type=click.Choice(["up", "down", "left", "right"]))
@click.option("--distance", "-d", type=float, default=0.5, help="Scroll distance as fraction of screen (0.0-1.0).")
@click.option("--duration", "-t", type=float, default=0.3, help="Scroll duration in seconds.")
@click.pass_context
def scroll(ctx: click.Context, direction: str, distance: float, duration: float) -> None:
    """Scroll the screen in a specified direction.

    Uses swipe gestures to scroll the screen. The swipe starts from the center
    of the screen and moves in the specified direction.

    DIRECTION: Direction to scroll (up, down, left, right).

    Examples:
        agentbridge scroll down           # Scroll down (reveals content below)
        agentbridge scroll up -d 0.8      # Scroll up with longer distance
        agentbridge scroll left -t 0.5    # Scroll left with slower animation
    """
    verbose = ctx.obj.get("verbose", False)
    d = get_device()

    # Get screen dimensions
    window_size = d.window_size()
    width, height = window_size[0], window_size[1]

    # Calculate center point
    center_x = width // 2
    center_y = height // 2

    # Calculate swipe distance in pixels
    scroll_distance_x = int(width * distance)
    scroll_distance_y = int(height * distance)

    # Determine start and end points based on direction
    # Note: Scrolling "down" means swiping up (finger moves up to reveal content below)
    if direction == "up":
        start_x, start_y = center_x, center_y - scroll_distance_y // 2
        end_x, end_y = center_x, center_y + scroll_distance_y // 2
    elif direction == "down":
        start_x, start_y = center_x, center_y + scroll_distance_y // 2
        end_x, end_y = center_x, center_y - scroll_distance_y // 2
    elif direction == "left":
        start_x, start_y = center_x - scroll_distance_x // 2, center_y
        end_x, end_y = center_x + scroll_distance_x // 2, center_y
    else:  # right
        start_x, start_y = center_x + scroll_distance_x // 2, center_y
        end_x, end_y = center_x - scroll_distance_x // 2, center_y

    if verbose:
        click.echo(f"Scrolling {direction}: ({start_x}, {start_y}) -> ({end_x}, {end_y})", err=True)

    try:
        d.swipe(start_x, start_y, end_x, end_y, duration=duration)

        # Output success as JSON
        result = {
            "action": "scroll",
            "direction": direction,
            "distance": distance,
            "duration": duration,
            "success": True,
        }
        click.echo(json.dumps(result))

    except Exception as e:
        output_json_error(f"Scroll failed: {e}", "SCROLL_FAILED")


@cli.command()
@click.pass_context
def home(ctx: click.Context) -> None:
    """Press the home button on the device.

    Returns the device to the home screen.

    Examples:
        agentbridge home
    """
    verbose = ctx.obj.get("verbose", False)
    d = get_device()

    if verbose:
        click.echo("Pressing home button", err=True)

    try:
        d.press("home")

        # Output success as JSON
        result = {
            "action": "home",
            "success": True,
        }
        click.echo(json.dumps(result))

    except Exception as e:
        output_json_error(f"Home button press failed: {e}", "HOME_FAILED")


@cli.command()
@click.pass_context
def back(ctx: click.Context) -> None:
    """Press the back button on the device.

    Navigates back in the current app or returns to the previous screen.

    Examples:
        agentbridge back
    """
    verbose = ctx.obj.get("verbose", False)
    d = get_device()

    if verbose:
        click.echo("Pressing back button", err=True)

    try:
        d.press("back")

        # Output success as JSON
        result = {
            "action": "back",
            "success": True,
        }
        click.echo(json.dumps(result))

    except Exception as e:
        output_json_error(f"Back button press failed: {e}", "BACK_FAILED")


# Allowed keys for the generic key command
ALLOWED_KEYS = frozenset([
    "home", "back", "enter", "menu", "recent",
    "volume_up", "volume_down", "power"
])


@cli.command()
@click.argument("key_name", type=str)
@click.pass_context
def key(ctx: click.Context, key_name: str) -> None:
    """Press a specific key on the device.

    Sends a key press event to the device. Supported keys are:
    home, back, enter, menu, recent, volume_up, volume_down, power.

    Examples:
        agentbridge key enter
        agentbridge key volume_up
        agentbridge key recent
    """
    verbose = ctx.obj.get("verbose", False)

    # Validate key name
    key_lower = key_name.lower()
    if key_lower not in ALLOWED_KEYS:
        output_json_error(
            f"Invalid key '{key_name}'. Allowed keys: {', '.join(sorted(ALLOWED_KEYS))}",
            "INVALID_KEY"
        )
        return

    d = get_device()

    if verbose:
        click.echo(f"Pressing {key_lower} key", err=True)

    try:
        d.press(key_lower)

        # Output success as JSON
        result = {
            "action": "key",
            "key": key_lower,
            "success": True,
        }
        click.echo(json.dumps(result))

    except Exception as e:
        output_json_error(f"Key press failed: {e}", "KEY_FAILED")


@cli.command()
@click.option("--path", "-p", type=click.Path(), help="Save screenshot to file path instead of base64 output.")
@click.option("--quality", "-q", type=int, default=80, help="JPEG quality (1-100) for base64 output.")
@click.pass_context
def screenshot(ctx: click.Context, path: str | None, quality: int) -> None:
    """Capture a screenshot of the device screen.

    By default, outputs the screenshot as a base64-encoded JPEG string.
    Use --path to save directly to a file instead.

    Examples:
        agentbridge screenshot                    # Output base64 JPEG
        agentbridge screenshot -p screen.png     # Save to file
        agentbridge screenshot -q 50             # Lower quality, smaller size
    """
    verbose = ctx.obj.get("verbose", False)
    d = get_device()

    if verbose:
        click.echo("Capturing screenshot...", err=True)

    try:
        # Capture screenshot as PIL Image
        img = d.screenshot()

        if path:
            # Save to file
            img.save(path)
            result = {
                "action": "screenshot",
                "path": path,
                "success": True,
            }
        else:
            # Convert to base64 JPEG
            import io
            buffer = io.BytesIO()
            img.save(buffer, format="JPEG", quality=quality)
            b64_data = base64.b64encode(buffer.getvalue()).decode("utf-8")
            result = {
                "action": "screenshot",
                "format": "jpeg",
                "quality": quality,
                "base64": b64_data,
                "success": True,
            }

        click.echo(json.dumps(result))

    except Exception as e:
        output_json_error(f"Screenshot failed: {e}", "SCREENSHOT_FAILED")


def _do_scan(ctx: click.Context, include_all: bool, compact: bool) -> None:
    """Internal implementation of scan/observe command.

    Args:
        ctx: Click context.
        include_all: If True, include all elements, not just interactive ones.
        compact: If True, output single-line JSON.
    """
    verbose = ctx.obj.get("verbose", False)

    if verbose:
        click.echo("Scanning UI hierarchy...", err=True)

    try:
        elements = get_interactive_tree(include_all=include_all)

        if verbose:
            click.echo(f"Found {len(elements)} elements", err=True)

        # Output JSON
        if compact:
            click.echo(json.dumps(elements, separators=(",", ":")))
        else:
            click.echo(json.dumps(elements, indent=2))

    except click.ClickException as e:
        output_json_error(str(e.message), "SCAN_FAILED")
    except Exception as e:
        output_json_error(f"Scan failed: {e}", "SCAN_FAILED")


@cli.command()
@click.option("--all", "-a", "include_all", is_flag=True, help="Include all elements, not just interactive ones.")
@click.option("--compact", "-c", is_flag=True, help="Output single-line JSON (no formatting).")
@click.pass_context
def scan(ctx: click.Context, include_all: bool, compact: bool) -> None:
    """Scan the current screen and output interactive elements as JSON.

    Parses the UI hierarchy, filters for interactive elements (clickable,
    scrollable, focusable, checkable), assigns numeric IDs, and outputs
    compressed JSON. Elements are cached for subsequent interaction commands.

    Output format:
      - id: Numeric identifier for the element
      - cls: Class name (shortened)
      - txt: Text content (truncated to 50 chars)
      - desc: Content description (truncated to 50 chars)
      - res: Resource ID (package prefix stripped)
      - bounds: {x, y, w, h} position and size
      - flags: Interaction flags (C=clickable, L=long-clickable, S=scrollable,
               F=focusable, K=checkable, k=checked, D=disabled, s=selected)
    """
    _do_scan(ctx, include_all, compact)


@cli.command()
@click.option("--all", "-a", "include_all", is_flag=True, help="Include all elements, not just interactive ones.")
@click.option("--compact", "-c", is_flag=True, help="Output single-line JSON (no formatting).")
@click.pass_context
def observe(ctx: click.Context, include_all: bool, compact: bool) -> None:
    """Alias for 'scan'. Scan the current screen and output interactive elements.

    This command is identical to 'scan' and is provided as an alternative name.
    See 'agentbridge scan --help' for full documentation.
    """
    _do_scan(ctx, include_all, compact)


def main() -> None:
    """Main entry point for the AgentBridge CLI."""
    cli()


if __name__ == "__main__":
    main()
