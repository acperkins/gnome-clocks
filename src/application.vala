/*
 * Copyright (C) 2013  Paolo Borelli <pborelli@gnome.org>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 */

namespace Clocks {

public class Application : Gtk.Application {
    const OptionEntry[] OPTION_ENTRIES = {
        { "version", 'v', 0, OptionArg.NONE, null, N_("Print version information and exit"), null },
        { (string) null }
    };

    const GLib.ActionEntry[] ACTION_ENTRIES = {
        { "stop-alarm", null, "s" },
        { "snooze-alarm", null, "s" },
        { "quit", on_quit_activate },
        { "add-location", on_add_location_activate, "v" }
    };

    private SearchProvider search_provider;
    private uint search_provider_id = 0;
    private World.ShellWorldClocks world_clocks;
    private uint world_clocks_id = 0;
    private Window? window;
    private List<string> system_notifications;

    private Window ensure_window () ensures (window != null) {
        if (window == null) {
            window = new Window (this);
        }
        return (Window) window;
    }

    public Application () {
        Object (application_id: Config.APP_ID);

        Gtk.Window.set_default_icon_name (Config.APP_ID);

        add_main_option_entries (OPTION_ENTRIES);
        add_action_entries (ACTION_ENTRIES, this);

        search_provider = new SearchProvider ();
        search_provider.activate.connect ((timestamp) => {
            var win = ensure_window ();
            win.show_world ();
            win.present_with_time (timestamp);
        });

        system_notifications = new List<string> ();
    }

    public override bool dbus_register (DBusConnection connection, string object_path) {
        try {
            search_provider_id = connection.register_object (object_path + "/SearchProvider", search_provider);
        } catch (IOError error) {
            printerr ("Could not register search provider service: %s\n", error.message);
        }

        try {
            world_clocks = new World.ShellWorldClocks (connection, object_path);
            world_clocks_id = connection.register_object (object_path, world_clocks);
        } catch (IOError error) {
            printerr ("Could not register world clocks service: %s\n", error.message);
        }

        return true;
    }

    public override void dbus_unregister (DBusConnection connection, string object_path) {
        if (search_provider_id != 0) {
            connection.unregister_object (search_provider_id);
            search_provider_id = 0;
        }

        if (world_clocks_id != 0) {
            connection.unregister_object (world_clocks_id);
            world_clocks_id = 0;
        }
    }

    protected override void activate () {
        base.activate ();

        var win = ensure_window ();
        win.present ();

        win.focus_in_event.connect (() => {
            withdraw_notifications ();

            return false;
        });
    }

    private void update_theme (Gtk.Settings settings) {
        string theme_name;

        settings.get ("gtk-theme-name", out theme_name);
        Utils.load_css ("gnome-clocks." + theme_name.down ());
    }

    protected override void startup () {
        base.startup ();

        Utils.load_css ("gnome-clocks");

        set_resource_base_path ("/org/gnome/clocks/");

        var theme = Gtk.IconTheme.get_default ();
        theme.add_resource_path ("/org/gnome/clocks/icons");

        var settings = (Gtk.Settings) Gtk.Settings.get_default ();
        settings.notify["gtk-theme-name"].connect (() => {
            update_theme (settings);
        });
        update_theme (settings);

        set_accels_for_action ("win.new", { "<Primary>n" });
        set_accels_for_action ("win.show-primary-menu", { "F10" });
        set_accels_for_action ("win.show-help-overlay", { "<Primary>question" });
        set_accels_for_action ("win.help", { "F1" });
        set_accels_for_action ("app.quit", { "<Primary>q" });
    }

    protected override int handle_local_options (GLib.VariantDict options) {
        if (options.contains ("version")) {
            print ("%s %s\n", (string) Environment.get_application_name (), Config.VERSION);
            return 0;
        }

        return -1;
    }

    public void on_add_location_activate (GLib.SimpleAction action, GLib.Variant? parameter) {
        if (parameter == null) {
            return;
        }

        var win = ensure_window ();
        win.show_world ();
        win.present ();

        var world = GWeather.Location.get_world ();
        if (world != null) {
            // The result is actually nullable
            var location = (GWeather.Location?) ((GWeather.Location) world).deserialize ((Variant) parameter);
            if (location != null) {
                win.add_world_location ((GWeather.Location) location);
            }
        } else {
            warning ("the world is missing");
        }
    }

    public new void send_notification (string notification_id, GLib.Notification notification) {
        base.send_notification (notification_id, notification);

        system_notifications.append (notification_id);
    }

    private void withdraw_notifications () {
        foreach (var notification in system_notifications) {
            withdraw_notification (notification);
        }
    }

    public override void shutdown () {
        base.shutdown ();

        withdraw_notifications ();
    }

    void on_quit_activate () {
        if (window != null) {
            ((Window) window).destroy ();
        }
        quit ();
    }
}

} // namespace Clocks
