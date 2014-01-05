/*
 * alan-watcher - watcher for alan2
 * Copyright (C) 2014  Semplice Project
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 * Authors:
 *    Eugenio "g7" Paolantonio <me@medesimo.eu>
*/

using Nala;

class AlanWatcher.Main : GLib.Object {

	class QueueHandler {
		/** Handler for the Queue. **/
		
		private Nala.Queue queue;
		
		public QueueHandler(Nala.Queue queue) {
			this.queue = queue;
		}
		
		public void add_to_queue(Nala.WatcherPool pool, Nala.Watcher watcher, File trigger, FileMonitorEvent event) {
			/** This method is fired when some event happened in our watcher/watcherpool. **/
			
			stdout.printf("Adding to queue, %s\n", trigger.get_path());
			this.queue.add_to_queue(watcher, trigger, event);
		}
		
	}


	static void reconfigure_openbox() {
		/** Reconfigures openbox. **/
		
		try {
			Process.spawn_command_line_sync("openbox --reconfigure");
		} catch (SpawnError e) {
			stderr.printf("ERROR: Unable to reconfigure openbox: %s\n", e.message);
		}
	
	}
	
	static void update_menu(Nala.Queue queue, Nala.Application[] apps, Array<string> in_queue_path, Array<string> in_queue_trigger, Array<FileMonitorEvent> in_queue_event) {
		/** Called when the queue timeout finishes. This method updates the menu. **/

		foreach(Nala.Application app in apps) {
			stdout.printf("Regenerating %s\n", app.path);
			
			try {
				Process.spawn_command_line_sync("alan-menu-updater " + app.path);
			} catch (SpawnError e) {
				stderr.printf("ERROR: Unable to update menu: %s\n", e.message);
			}
		}
		
		reconfigure_openbox();
	}
	
	static int main() {
		/** Hello! **/
		
		Nala.WatcherPool pool = new Nala.WatcherPool();
		Nala.Queue queue = new Nala.Queue(3);
		QueueHandler queueh = new QueueHandler(queue);
		Gee.HashMap<string, Nala.Application> applications_objects = new Gee.HashMap<string, Nala.Application>();

		pool.watcher_changed.connect(queueh.add_to_queue);
		queue.processable.connect(update_menu);

		// Wanna some setup?
		var dir = File.new_for_path(Environment.get_home_dir() + "/.config/alan-menus");
		if (!dir.query_exists()) {
			// Doing setup
			try {
				// FIXME: semplice is hardcoded
				Process.spawn_command_line_sync("/usr/share/alan2/alan2-setup.sh semplice");
			} catch (SpawnError e) {
				stderr.printf("ERROR: Unable to setup alan2: %s\n", e.message);
				return 1;
			}
			
			
			reconfigure_openbox();
		}
		
		// Parse watchers
		try {
			var watcher_directory = File.new_for_path("/etc/alan/watchers");
			var watcher_enumerator = watcher_directory.enumerate_children(FileAttribute.STANDARD_NAME, 0);
			FileInfo file_info;
			while ((file_info = watcher_enumerator.next_file()) != null) {
				KeyFile watcher = new KeyFile();
				watcher.load_from_file("/etc/alan/watchers/" + file_info.get_name(), KeyFileFlags.NONE);
				string application = watcher.get_string("nala", "application");				
				
				// Get files
				string[] files = new string[0];
				if (watcher.has_key("nala", "files")) {
					foreach(string file in watcher.get_string("nala", "files").split(" ")) {
						files += file.replace("~", Environment.get_home_dir());
					}
				}
				files += "/etc/alan/alan.conf";
				files += Environment.get_home_dir() + "/.config/alan/alan.conf";
				files += Environment.get_home_dir() + "/.gtkrc-2.0";
				
				// Generate application and add to pool and queue
				Nala.Application app = new Nala.Application(application, files);
				applications_objects[application] = app;
				pool.add_watchers(app.triggers);
				queue.add_application(app);
			}
		} catch (Error e) {
			stderr.printf("ERROR: Unable to access to the watchers directory.");
			return 1;
		}
		
		
		// Ladies and gentlemen...
		new MainLoop().run();
		
		return 0;
	}
}
