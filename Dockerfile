FROM ghcr.io/cirruslabs/flutter:stable AS build

WORKDIR /app

COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .

RUN flutter build web
RUN dart compile exe bin/webui_server.dart -o /tmp/pathplanner_webui_server

FROM dart:stable AS runtime

WORKDIR /app

COPY --from=build /tmp/pathplanner_webui_server /app/pathplanner_webui_server
COPY --from=build /app/build/web /app/build/web
COPY --from=build /app/images /app/images

RUN mkdir -p /app/webui_data/teams

EXPOSE 8080
VOLUME ["/app/webui_data"]

ENTRYPOINT ["/app/pathplanner_webui_server"]
CMD ["--host=0.0.0.0", "--port=8080", "--web-dir=/app/build/web", "--data-dir=/app/webui_data"]
