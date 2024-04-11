FROM jupyter/base-notebook:latest

# Install .NET CLI dependencies

ARG NB_USER=jovyan
ARG NB_UID=1000
ENV USER ${NB_USER}
ENV NB_UID ${NB_UID}
ENV HOME /home/${NB_USER}

WORKDIR ${HOME}

USER root

ENV \
  # Enable detection of running in a container
  DOTNET_RUNNING_IN_CONTAINER=true \
  # Enable correct mode for dotnet watch (only mode supported in a container)
  DOTNET_USE_POLLING_FILE_WATCHER=true \
  # Skip extraction of XML docs - generally not useful within an image/container - helps performance
  NUGET_XMLDOC_MODE=skip \
  # Opt out of telemetry until after we install jupyter when building the image, this prevents caching of machine id
  DOTNET_INTERACTIVE_CLI_TELEMETRY_OPTOUT=true \
  # Go Version
  GO_VERSION=1.21.0 \
  # Go Root Path
  GOROOT=/usr/share/go \
  # Go Path
  GOPATH=${HOME}/go
  
# Go Path Set
ENV PATH="$PATH:$GOROOT/bin:$GOPATH/bin"
RUN echo "$PATH"  \
  && mkdir -p "$GOROOT" \
  && mkdir -p /usr/bin/dotnet \
  && ln -s "$GOROOT" /usr/bin/dotnet

# Install .NET CLI dependencies
RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  libc6 \
  libgcc1 \
  libgssapi-krb5-2 \
  libssl3 \
  libicu-dev \
  libstdc++6 \
  zlib1g \
  apt-utils >/dev/null 2>&1 \
  && rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y curl wget git

RUN jupyter --data-dir

# Install Go
RUN wget --quiet --output-document=- "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" | tar -xz \
    && go version

# Run sed command with kernel.json.in
RUN \
  go install github.com/gopherdata/gophernotes@v0.7.5 \
  mkdir -p ~/.local/share/jupyter/kernels/gophernotes \
  cd ~/.local/share/jupyter/kernels/gophernotes \
  cp "$(go env GOPATH)"/pkg/mod/github.com/gopherdata/gophernotes@v0.7.5/kernel/*  "." \
  # in case copied kernel.json has no write permission
  chmod +w ./kernel.json \
  COPY ./kernel.json.in /tmp/kernel.json.in \
  sed "s|gophernotes|$(go env GOPATH)/bin/gophernotes|" < /tmp/kernel.json.in > kernel.json \
  "$(go env GOPATH)"/bin/gophernotes

# Install .NET Core SDK

# When updating the SDK version, the sha512 value a few lines down must also be updated.
ENV DOTNET_SDK_VERSION 7.0.203

RUN dotnet_sdk_version=7.0.203 \
  && curl -SL --output dotnet.tar.gz https://dotnetcli.azureedge.net/dotnet/Sdk/$dotnet_sdk_version/dotnet-sdk-$dotnet_sdk_version-linux-x64.tar.gz \
  && dotnet_sha512='ed1ae7cd88591ec52e1515c4a25d9a832eca29e8a0889549fea35a320e6e356e3806a17289f71fc0b04c36b006ae74446c53771d976c170fcbe5977ac7db1cb6' \
  && echo "$dotnet_sha512 dotnet.tar.gz" | sha512sum -c - \
  && mkdir -p /usr/share/dotnet \
  && tar -ozxf dotnet.tar.gz -C /usr/share/dotnet \
  && rm dotnet.tar.gz \
  && ln -s /usr/share/dotnet/dotnet /usr/bin/dotnet \
  # Trigger first run experience by running arbitrary cmd
  && dotnet help

# Copy notebooks

COPY ./notebooks/ ${HOME}/notebooks/

# Add package sources
RUN echo "\
  <configuration>\
  <solution>\
  <add key=\"disableSourceControlIntegration\" value=\"true\" />\
  </solution>\
  <packageSources>\
  <clear />\
  <add key=\"dotnet-experimental\" value=\"https://pkgs.dev.azure.com/dnceng/public/_packaging/dotnet-experimental/nuget/v3/index.json\" />\
  <add key=\"dotnet-public\" value=\"https://pkgs.dev.azure.com/dnceng/public/_packaging/dotnet-public/nuget/v3/index.json\" />\
  <add key=\"dotnet-eng\" value=\"https://pkgs.dev.azure.com/dnceng/public/_packaging/dotnet-eng/nuget/v3/index.json\" />\
  <add key=\"dotnet-tools\" value=\"https://pkgs.dev.azure.com/dnceng/public/_packaging/dotnet-tools/nuget/v3/index.json\" />\
  <add key=\"dotnet-libraries\" value=\"https://pkgs.dev.azure.com/dnceng/public/_packaging/dotnet-libraries/nuget/v3/index.json\" />\
  <add key=\"dotnet5\" value=\"https://pkgs.dev.azure.com/dnceng/public/_packaging/dotnet5/nuget/v3/index.json\" />\
  <add key=\"MachineLearning\" value=\"https://pkgs.dev.azure.com/dnceng/public/_packaging/MachineLearning/nuget/v3/index.json\" />\
  </packageSources>\
  <disabledPackageSources />\
  </configuration>\
  " > ${HOME}/NuGet.config

RUN chown -R ${NB_UID} ${HOME}
USER ${USER}


# Install nteract 
RUN pip install nteract_on_jupyter \
jupyter_contrib_nbextensions

# Install lastest build of Microsoft.DotNet.Interactive
#RUN dotnet tool install -g Microsoft.dotnet-interactive --add-source "https://pkgs.dev.azure.com/dnceng/public/_packaging/dotnet-experimental/nuget/v3/index.json"

# Latest stable from nuget.org
RUN dotnet tool install -g Microsoft.dotnet-interactive --add-source "https://api.nuget.org/v3/index.json"

ENV PATH="${PATH}:${HOME}/.dotnet/tools"
RUN echo "$PATH"

# Install kernel specs
RUN dotnet interactive jupyter install

# Enable telemetry once we install jupyter for the image
ENV DOTNET_INTERACTIVE_CLI_TELEMETRY_OPTOUT=false

# Install tslab
RUN npm install -g tslab yarn
RUN tslab install
RUN tslab install --version \
&& jupyter kernelspec list

# Clone tslab-examples
RUN tslab_path=${HOME}/notebooks/tslab \
&& git clone --depth 1 https://github.com/yunabe/tslab-examples.git $tslab_path \
&& cd $tslab_path \
&& yarn

# Set root to notebooks
WORKDIR ${HOME}/notebooks/
