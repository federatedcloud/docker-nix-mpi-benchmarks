FROM cornellcac/nix_alpine_base:0f566286984d3565f89262acb3186483832bdae8

# variables exported from https://github.com/federatedcloud/NixTemplates/blob/develop/Dockerfile-Base
# $nixuser
# $nixenv
# $ENVSDIR

USER root
ARG ADDUSER

COPY config.nix $HOME/.config/nixpkgs/
COPY prod-env.nix $ENVSDIR/
COPY persist-env.sh $ENVSDIR/
RUN chown -R $nixuser:$nixuser $ENVSDIR

# for MPI orted daemon to properly spawn on worker containers, we need the orted binary on the noninteractive ssh PATH
#   for Alpine, some alternatives such as /etc/profile and per user ssh environment were attempted but did not succeed
#   instead we place many links including to the mpi orted binary in a location on the default noninteractive ssh PATH
RUN for i in $(ls /nixenv/nixuser/.nix-profile/bin) ; do ln -s /nixenv/nixuser/.nix-profile/bin/"$i" /usr/bin ; done
#RUN sed -i 's|^nixuser.*|nixuser:x:1000:1000::/home/nixuser:/nixenv/nixuser/.nix-profile/bin/bash|' /etc/passwd

#
# Initialize environment a bit for faster container spinup/use later
#
USER $nixuser
RUN $nixenv && cd /tmp && sh $ENVSDIR/persist-env.sh $ENVSDIR/prod-env.nix
#

USER root

#
# Security Note : root login and user environment could be dangerous settings,
#     these should only be applied to worker nodes (aka cloud VMs) on a private
#     subnet only, accessed by the user through an ssh bastion server.
#     Explicit sshd port exposure under common deployments means that Docker
#     default network isolation does not help in this regard. Ssh port
#     listening is necessary in order to launch mpi processes.
#
# The below method isn't ideal, as it could break - better to copy in an sshd_config file
# or somehow use nix to configure sshd
# sed -i 's/.*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
#
# alternatively ...:
# TODO: write a script to check if PermitRootLogin is already set, and replace it if so, else add it
#
ENV SSHD_PATH ""
RUN SSHD_PATH=$(su -c "$nixenv && nix-build '<nixpkgs>' --no-build-output --no-out-link -A openssh" "${nixuser:?}") && \
  mkdir -p /etc/ssh && cp "$SSHD_PATH/etc/ssh/sshd_config" /etc/ssh/sshd_config && \
  mkdir /var/run/sshd && \
  printf "PermitRootLogin yes\n" >> /etc/ssh/sshd_config && \
  printf "PermitUserEnvironment yes\n" >> /etc/ssh/sshd_config && \
  id -u sshd || ${ADDUSER} sshd && \
  mkdir -p /var/empty/sshd/etc && \
  cd /var/empty/sshd/etc && \
  ln -s /etc/localtime localtime
  
USER $nixuser


# ------------------------------------------------------------
# Set-Up SSH with our Github deploy key
# ------------------------------------------------------------

ENV SSHDIR ${HOME}/.ssh/

RUN mkdir -p ${SSHDIR}

ADD ssh/config ${SSHDIR}/config
ADD ssh/id_rsa.mpi ${SSHDIR}/id_rsa
ADD ssh/id_rsa.mpi.pub ${SSHDIR}/id_rsa.pub
ADD ssh/id_rsa.mpi.pub ${SSHDIR}/authorized_keys

ADD mpi_hostfile ${HOME}/mpi_hostfile

USER root

RUN chmod -R 600 ${SSHDIR}* && \
    chown -R ${nixuser}:${nixuser} ${SSHDIR}

# ------------------------------------------------------------
# Configure OpenMPI
# ------------------------------------------------------------

RUN rm -fr ${HOME}/.openmpi && mkdir -p ${HOME}/.openmpi
ADD default-mca-params.conf ${HOME}/.openmpi/mca-params.conf
RUN chown -R ${nixuser}:${nixuser} ${HOME}/.openmpi

# ------------------------------------------------------------
# Any benchmarks specifics will go here
# ------------------------------------------------------------
# TODO: copy a runscript in!

# ------------------------------------------------------------
# Nix stuff
# ------------------------------------------------------------
USER $nixuser

ARG SSH_PRIVATE_KEY
COPY dev.nix $ENVSDIR/
#TODO: Running echo and rm in the same line seems to be fine. If this method does not work, I would look into Multi-stage builds in Docker 
RUN echo "$SSH_PRIVATE_KEY" > ${HOME}/tmp_rsa && chmod 600 ${HOME}/tmp_rsa && \
  rm -f ${HOME}/tmp_rsa && sed -i '$d' ${SSHDIR}/config | sed -i '$d' ${SSHDIR}/config   

USER root

RUN passwd -d $nixuser

# optional - Prep dev environment ahead of time
RUN nix-shell ${ENVSDIR}/dev.nix

# ------------------------------------------------------------
# Entrypoint
# ------------------------------------------------------------

ENV TRIGGER 1


#Copy this last to prevent rebuilds when changes occur in them:
COPY entrypoint* $ENVSDIR/
#COPY dev.nix $ENVSDIR/

RUN chown $nixuser:$nixuser $ENVSDIR/entrypoint
ENV PATH="${PATH}:/usr/local/bin"

EXPOSE 22
ENTRYPOINT ["/bin/sh", "./entrypoint"]
