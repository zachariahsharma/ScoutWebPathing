# PathPlanner Scouting Web UI

This repo now contains only the web scouting UI and its small local API server for charting observed autonomous routines from match footage. It focuses on:
* Drawing timestamped path points on the field
* Previewing the robot on the path
* Organizing autos by server-side team folders
* Browsing each team's saved autos
* Exporting each auto as JSON
* Exporting a team's autos as a PDF

### Run in development
1. Start the backend server:
   * `dart run bin/webui_server.dart --port=8080`
2. Start the Flutter web UI in a second terminal:
   * `flutter run -d chrome --dart-define=PATHPLANNER_WEBUI_API=http://127.0.0.1:8080`

Saved files will be written to `webui_data/teams/<team>/<auto>.json`.

### Build for deployment
1. Build the Flutter web bundle:
   * `flutter build web`
2. Serve the bundle and API together:
   * `dart run bin/webui_server.dart --port=8080 --web-dir=build/web`
