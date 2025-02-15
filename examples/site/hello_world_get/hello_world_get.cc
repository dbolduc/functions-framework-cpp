// Copyright 2020 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// [START functions_helloworld_get]
#include <google/cloud/functions/http_request.h>
#include <google/cloud/functions/http_response.h>

namespace gcf = ::google::cloud::functions;

// Though not used in this example, the request is passed by value to support
// applications that move-out its data.
gcf::HttpResponse hello_world_get(gcf::HttpRequest) {  // NOLINT
  return gcf::HttpResponse{}
      .set_header("content-type", "text/plain")
      .set_payload("Hello World!");
}
// [END functions_helloworld_get]
