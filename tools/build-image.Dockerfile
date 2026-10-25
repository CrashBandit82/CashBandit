FROM eclipse-temurin:17-jdk
RUN apt-get update -qq && apt-get install -y -qq git unzip xz-utils curl zip libglu1-mesa python3-pil sqlite3 libsqlite3-dev clang >/dev/null && rm -rf /var/lib/apt/lists/*
RUN git config --system --add safe.directory "*"
