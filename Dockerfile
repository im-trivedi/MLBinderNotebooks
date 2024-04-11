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
  DOTNET_INTERACTIVE_CLI_TELEMETRY_OPTOUT=true 

ENV PATH="$PATH:/usr/local/go/bin"

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

RUN rm -rf /usr/local/go && wget --quiet --output-document=- "https://go.dev/dl/go1.22.2.linux-amd64.tar.gz" | tar -xz -C /usr/local
  
RUN go version

RUN go install github.com/gopherdata/gophernotes@v0.7.5

RUN mkdir -p ~/.local/share/jupyter/kernels/gophernotes \
  && cd ~/.local/share/jupyter/kernels/gophernotes

RUN cp "$(go env GOPATH)"/pkg/mod/github.com/gopherdata/gophernotes@v0.7.5/kernel/*  "." 

RUN pwd && ls -l

# Install .NET Core SDK

# When updating the SDK version, the sha512 value a few lines down must also be updated.
ENV DOTNET_SDK_VERSION 8.0.204

RUN dotnet_sdk_version=8.0.204 \
  && curl -SL --output dotnet.tar.gz https://dotnetcli.azureedge.net/dotnet/Sdk/$dotnet_sdk_version/dotnet-sdk-$dotnet_sdk_version-linux-x64.tar.gz \
  && dotnet_sha512='b45d3e3bc039d50764bfbe393b26cc929d93b22d69da74af6d35d4038ebcbc2f8410b047cdd0425c954d245e2594755c9f293c09f1ded3c97d33aebfaf878b5f' \
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
