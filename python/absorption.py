from __future__ import print_function
import sys
import numpy as np
from scipy import sparse
from scipy.sparse import linalg
import fileinput
import time

verbosity = 0

def eprint(*args, verb=0, **kwargs):
    if verb <= verbosity:
        print(*args, file=sys.stderr, **kwargs)

def get_transient(X, absorbing):
    transient = np.zeros(len(absorbing), dtype='bool_')
    (worklist,) = np.nonzero(absorbing)
    worklist = worklist.tolist()
    
    preds = [[] for _ in range(len(absorbing))]
    ii,jj = X.nonzero()
    for i,j in zip(ii,jj):
        # don't consider predecessors of the emtpy set!
        if j != 0:
            preds[j].append(i)

    while worklist:
        s = worklist.pop()
        for pred in preds[s]:
            if transient[pred]: continue
            transient[pred] = True
            worklist.append(pred)
    (transient_idxs,) = np.nonzero(transient)
    # states that are neither transient not absorbing are singular
    (singular_idxs,) = np.nonzero((~transient) & (~absorbing))
    return transient_idxs, singular_idxs



def main():
    eprint("[python] waiting for input matrices ...", verb=1)

    # load matrices
    (AP, (nq,nq_)) = read_matrix()
    eprint("[python] AP received (%dx%d)!" % (nq, nq_), flush=True, verb=2)
    (not_a, nr) = read_vector()
    eprint("[python] not_a received (%dx1)!" % nr, flush=True, verb=2)
    assert(nq == nq_ == nr)
    n = nq
    eprint("[python] %dx%d matrices received!" % (n, n), verb=1)

    # print received matrices
    # eprint("[python] AP =\n", AP.toarray(), verb=3)
    # eprint("[python] not_a =\n", not_a, verb=3)

    # # need to handle 1-dimensionoal case seperately
    # if n == 1:
    #     if not_a[0] == 1:
    #         # return all-ones matrix
    #         write_matrix(sparse.eye(1, 1))
    #     else:
    #         # return all-zeros matrix
    #         write_matrix(sparse.dok_matrix((1,1), dtype='d'))
    #     exit(0)

    # first, check wich states can even reach an absorbing state ever
    start = time.process_time()
    AP[0,0] = 0 # the empty set is always absorbing
    (transient,singular) = get_transient(AP, not_a)
    n_abs = sum(not_a)
    eprint("--> python reachabilty computation: %f seconds" % (time.process_time() - start), verb=0)

    start = time.process_time()
    (absorbing,) = np.nonzero(not_a)
    n_trans = transient.size
    n_sing = singular.size
    # the state space is partioned into singular, transient, and absorbing states
    assert(n_sing + n_trans + n_abs == n)
    eprint("--> python index computation: %f seconds" % (time.process_time() - start), verb=0)
    eprint("[python] non-singular transient = ", transient, verb=2)
    eprint("[python] n = %d, n_abs = %d, n_trans = %d, n_singular = %d" 
           % (n, n_abs, n_trans, n - n_abs - n_trans), verb=1)

    # solve sparse linear system to compute absorption probabilities
    start = time.process_time()
    AP = AP.tocsr()[transient,:].tocsc()
    A = sparse.eye(transient.size).tocsc() - AP[:,transient]
    R = AP[:, absorbing]
    eprint("--> python slicing time: %f seconds" % (time.process_time() - start), verb=0)

    start = time.process_time()
    X = linalg.spsolve(A, R)
    eprint("--> python solver time: %f seconds" % (time.process_time() - start), verb=0)
    XX = sparse.lil_matrix((n, n), dtype='d')
    XX[np.ix_(transient, absorbing)] = X
    for i in absorbing:
        XX[i,i] = 1
    XX[singular,0] = 1

    # write matrix back
    write_matrix(XX)

def read_matrix():
    (M, N) = sys.stdin.readline().split()
    shape = (int(M), int(N))
    eprint("[python] receiving matrix of size %sx%s" % (M,N), verb=1)
    I = []; J = []; V = [];
    # A = sparse.lil_matrix(shape, dtype='d')
    for line in sys.stdin:
        parts = line.split()
        if len(parts) == 0:
            # end of input
            A = sparse.csr_matrix((V,(I,J)), shape=shape)
            return (A, shape)
        elif len(parts) == 3:
            (i, j, a) = parts
            I.append(int(i))
            J.append(int(j))
            V.append(np.float64(a))
        else:
            raise NameError("unepexted input line: %s" % line)
    raise NameError("reachead end of input stream before end of matrix!")

def read_vector():
    (M, N) = sys.stdin.readline().split()
    assert(M == N)
    shape = int(M)
    v = np.zeros(shape, dtype='bool_')
    for line in sys.stdin:
        # eprint("[python] received: \"%s\"" % line.strip(), verb=4)
        parts = line.split()
        if len(parts) == 0:
            # end of input
            return (v, shape)
        elif len(parts) == 3:
            (i, j, a) = parts
            i,j = int(i), int(j)
            a = bool(a)

            # we are parsing a predicate
            # hence, entries must be in {0,1} ...
            assert (a == True)
            # ... and nonzero entries are either on the diagonal or in the 0-column
            if j == i:
                v[i] = a
            else:
                assert (j == 0)
        else:
            raise NameError("unepexted input line: %s" % line)
    raise NameError("reachead end of input stream before end of vector!")


def write_matrix(A):
    (M, N) = A.shape
    print('%d %d' % (M, N))
    A = A.tocoo()
    for i,j,v in zip(A.row, A.col, A.data):
        print('%d %d %s' % (i,j,repr(v)))


if __name__ == '__main__':
    if len(sys.argv) != 1:
        print("usage: %s" % sys.argv[0])
        exit(1)
    try:
        main()
    except BrokenPipeError:
        eprint("[python] pipe closed, shutting down...")
    finally:
        exit(0)