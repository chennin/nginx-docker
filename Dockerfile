ARG DISTRIB_CODENAME="trixie"
FROM debian:${DISTRIB_CODENAME}-slim AS build
ENV NGINX_GPGKEY_PATH=/usr/share/keyrings/nginx-archive-keyring.gpg
ENV DEBIAN_FRONTEND=noninteractive
ENV CFLAGS="-O3 -march=x86-64-v3 -mtune=generic -pipe -fno-plt -fstack-clash-protection"
ENV CXXFLAGS="${CFLAGS}"
ENV NGINX_REPO="https://nginx.org/packages/debian/"
USER root
RUN         apt-get update && apt-get install --no-install-recommends -y ca-certificates gnupg curl \
            && curl --silent --fail https://nginx.org/keys/nginx_signing.key | gpg --dearmor | tee $NGINX_GPGKEY_PATH >/dev/null
ARG DISTRIB_CODENAME
ARG NTMPDIR=/tmp/custom-build
RUN         echo "deb [signed-by=$NGINX_GPGKEY_PATH] $NGINX_REPO $DISTRIB_CODENAME nginx" > /etc/apt/sources.list.d/nginx.list \
            && echo "deb-src [signed-by=$NGINX_GPGKEY_PATH] $NGINX_REPO $DISTRIB_CODENAME nginx" >> /etc/apt/sources.list.d/nginx.list \
            && mkdir -p "$NTMPDIR" && chmod 777 "${NTMPDIR}" \
            && apt-get update \
            && apt-get build-dep -y nginx \
            && apt-get install -y --no-install-recommends git bison build-essential ca-certificates curl dh-autoreconf doxygen flex gawk \
                               git iputils-ping libcurl4-openssl-dev libexpat1-dev libgeoip-dev liblmdb-dev libssl-dev libtool libxml2 \
                               libxml2-dev libyajl-dev locales liblua5.4-dev pkg-config wget zlib1g-dev libxslt-dev libgd-dev libpcre2-dev \
                               libfuzzy-dev
ARG MS_VERS
RUN         cd "$NTMPDIR" \
            && git clone --depth=1  -c advice.detachedHead=false --single-branch --branch $MS_VERS https://github.com/owasp-modsecurity/ModSecurity && cd ModSecurity \
            && git submodule init && git submodule update --init --recursive \
            && ./build.sh && ./configure --with-pcre2 --with-ssdeep && make -j $(( $(nproc) / 2 + 1 )) && make install
ARG SET_MISC_VERS
ARG NDK_VERS
RUN         cd "$NTMPDIR" \
            && git clone --depth=1  -c advice.detachedHead=false --single-branch --branch $SET_MISC_VERS https://github.com/openresty/set-misc-nginx-module.git && cd set-misc-nginx-module && cd .. \
            && git clone --depth=1  -c advice.detachedHead=false --single-branch --branch $NDK_VERS https://github.com/vision5/ngx_devel_kit.git && cd ngx_devel_kit
ARG MS_NG_VERS
RUN         cd "$NTMPDIR" && apt-get -y --no-install-recommends install nginx \
            && git clone --depth=1  -c advice.detachedHead=false --single-branch --branch $MS_NG_VERS https://github.com/owasp-modsecurity/ModSecurity-nginx.git && cd ModSecurity-nginx && cd .. \
            && apt-get source nginx && CARGS=$(nginx -V 2>&1 | grep "^configure arguments:" | cut -d' ' -f3-) \
            && NGINX_VERSION=$(nginx -V 2>&1 | grep "^nginx version:" | cut -d/ -f2) && cd "nginx-${NGINX_VERSION}" \
            && eval "./configure --add-dynamic-module=../ngx_devel_kit --add-dynamic-module=../set-misc-nginx-module --add-dynamic-module=../ModSecurity-nginx ${CARGS}" \
            && make -j $(( $(nproc) / 2 + 1 )) modules && cp -p objs/*.so /usr/lib/nginx/modules/
RUN         nginx -v 2>&1 | sed -e 's/nginx /nginx_/' >/.version && echo "NDK: ${NDK_VERS}\nset_misc: ${SET_MISC_VERS}\nModSecurity-nginx: ${MS_NG_VERS}\nModSecurity: ${MS_VERS}" >> /.version

ARG DISTRIB_CODENAME
FROM debian:${DISTRIB_CODENAME}-slim
ARG MS_VERS
ARG MS_NG_VERS
ARG NDK_VERS
ARG SET_MISC_VERS
ARG CRS_VERSION
LABEL VERSION_ModSecurity="${MS_VERS}"
LABEL VERSION_ModSecurity_nginx="${MS_NG_VERS}"
LABEL VERSION_NDK="${NDK_VERS}"
LABEL VERSION_set_misc="${SET_MISC_VERS}"
LABEL VERSION_CRS="${CRS_VERSION}"
ARG CRS_VERSION
ENV DEBIAN_FRONTEND=noninteractive
# Don't use a variable
COPY --from=build /usr/share/keyrings/nginx-archive-keyring.gpg /usr/share/keyrings/nginx-archive-keyring.gpg
COPY --from=build /etc/apt/sources.list.d/nginx.list /etc/apt/sources.list.d/nginx.list
RUN apt-get update && apt-get -y --no-install-recommends install ca-certificates gnupg && apt-get update && \
    apt-get -yV --no-install-recommends install nginx curl libcurl4 libyajl2 liblua5.4-0 libfuzzy2 libgeoip1 libxml2 \
    && apt-get purge -y --auto-remove && rm -rf /var/lib/apt/* && rm -rf /var/cache/debconf/* && find /var/log -type f -delete \
    && ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log
RUN mkdir -p /usr/local/coreruleset && curl -sL --output /tmp/${CRS_VERSION}.tar.gz https://github.com/coreruleset/coreruleset/archive/refs/tags/${CRS_VERSION}.tar.gz && \
    tar xf /tmp/${CRS_VERSION}.tar.gz --strip-components=1 -C /usr/local/coreruleset && rm /tmp/${CRS_VERSION}.tar.gz
COPY --from=build /usr/local/modsecurity/lib /usr/local/modsecurity/lib
COPY --from=build /usr/lib/nginx/modules/* /usr/lib/nginx/modules/
COPY --from=build /tmp/custom-build/ModSecurity/unicode.mapping /etc/nginx/
COPY --from=build /.version /.version
RUN echo "Coreruleset: ${CRS_VERSION}" >> /.version
EXPOSE 80 443
CMD ["nginx", "-g", "daemon off;"]
