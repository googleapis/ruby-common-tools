# Copyright 2021 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

FROM ruby:3.4.5-bookworm
RUN apt-get update \
    && apt-get -y upgrade \
    && apt-get -y autoremove \
    && apt-get -y autoclean
RUN mkdir /ruby-postprocessor \
    && gem install toys:0.15.6 rexml:3.4.0
WORKDIR /ruby-postprocessor
COPY lib/*.rb /ruby-postprocessor/
COPY lib/owlbot /ruby-postprocessor/owlbot
COPY *.md /ruby-postprocessor/
RUN mkdir -p /user-home/.cache \
    && mkdir -p /user-home/.bundle \
    && chmod -R 777 /user-home
ENV HOME=/user-home \
    XDG_CACHE_HOME=/user-home/.cache \
    BUNDLE_PATH=/user-home/.bundle
ENTRYPOINT ["ruby", "/ruby-postprocessor/entrypoint.rb"]
CMD []
