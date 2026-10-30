<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
                xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:g="urn:xmlast:grammar"
                xmlns:c="urn:xmlast:comment" xmlns:t="urn:xmlast:token"
                xmlns:l="urn:xmlast:lineage" xmlns:fn="urn:xmlast:functions"
                xmlns:m="urn:git:metadata"
                xmlns:r="urn:xmlast:graph"
                exclude-result-prefixes="xs fn g t c l" expand-text="yes" version="3.0">
    <xsl:param name="collection"/>
    <xsl:param name="schema"/>

    <xsl:param name="select-pattern" select="'*.xir'"/>
    <xsl:output method="xml" indent="yes"/>
    <xsl:strip-space elements="*"/>
    <xsl:mode on-no-match="shallow-copy"/>

    <xsl:function name="fn:strip-query" as="xs:string">
        <xsl:param name="uri" as="xs:string?"/>
        <xsl:sequence select="replace(normalize-space($uri), '\?.*$', '')"/>
    </xsl:function>

    <xsl:function name="fn:parent-dir-uri" as="xs:string">
        <xsl:param name="uri" as="xs:string?"/>
        <xsl:variable name="base" select="replace(fn:strip-query($uri), '/+$', '')" as="xs:string"/>
        <xsl:variable name="parent" select="replace($base, '/[^/]*$', '')" as="xs:string"/>
        <xsl:sequence select="if (ends-with($parent, '/')) then $parent else $parent || '/'"/>
    </xsl:function>

    <xsl:function name="fn:schema-matches-doc" as="xs:boolean">
        <xsl:param name="doc" as="document-node()"/>
        <xsl:param name="schema-name" as="xs:string?"/>
        <xsl:variable name="schema-lc" select="lower-case(normalize-space($schema-name))" as="xs:string"/>
        <xsl:variable name="uri" select="lower-case(string((document-uri($doc), base-uri($doc))[1]))" as="xs:string"/>
        <xsl:variable name="prefix" select="$schema-lc || '.'" as="xs:string"/>
        <xsl:variable name="table-refs" as="xs:string*"
                      select="($doc//to/@name, $doc//from/@name) ! lower-case(normalize-space(.))"/>
        <xsl:variable name="procedure-refs" as="xs:string*"
                      select="$doc//procedure/@name ! lower-case(normalize-space(.))"/>
        <xsl:variable name="call-schemas" as="xs:string*"
                      select="$doc//call/@schema ! lower-case(normalize-space(.))"/>
        <xsl:sequence select="
            if ($schema-lc = '') then true()
            else contains('/' || $uri || '/', '/' || $schema-lc || '/')
                 or (some $p in $procedure-refs satisfies starts-with($p, $prefix))
                 or (some $t in $table-refs satisfies starts-with($t, $prefix))
                 or (some $c in $call-schemas satisfies $c = $schema-lc)"/>
    </xsl:function>

    <xsl:function name="fn:safe-collection" as="document-node()*">
        <xsl:param name="uri" as="xs:string"/>
        <xsl:try>
            <xsl:sequence select="collection($uri)"/>
            <xsl:catch errors="*">
                <xsl:sequence select="()"/>
            </xsl:catch>
        </xsl:try>
    </xsl:function>
    <!--
        Toplevel Scan all procedures
      -->
    <xsl:template match="/">
        <xsl:variable name="primary-collection"
                      select="concat($collection, '?on-error=ignore;recurse=yes;select=', $select-pattern)"/>
        <xsl:variable name="primary-docs" select="fn:safe-collection($primary-collection)" as="document-node()*"/>
        <xsl:variable name="fallback-collection"
                      select="concat(fn:parent-dir-uri($collection), '?on-error=ignore;recurse=yes;select=', $select-pattern)"/>
        <xsl:variable name="resolved-docs"
                      select="if (exists($primary-docs)) then $primary-docs else fn:safe-collection($fallback-collection)"
                      as="document-node()*"/>
        <xsl:variable name="docs" select="$resolved-docs[fn:schema-matches-doc(., $schema)]" as="document-node()*"/>
        <xsl:variable name="currentDate" select="xs:string(current-dateTime())"/>
        <xsl:variable name="currentDateFmt" select="replace(normalize-space($currentDate),
            '^(\d{2})-(\d{2})-(\d{4})\s+(.*)','$3-$1-$2T$4Z')"/>
<!--        <xsl:variable name="procedures" select="$docs/g:ast/l:lineage-sequence[@type='procedure']"/>-->
        <xsl:variable name="procedures" select="$docs//procedure"/>

        <l:procedures xmlns:l="urn:xmlast:lineage"
                      schema="{$schema}"
                      collection="{$collection}"
                      creation-date="{$currentDateFmt}"
                      count="{count($procedures)}">

            <xsl:for-each select="$procedures">
                <xsl:sort select="@name"/>
                <xsl:variable name="name" select="@name"/>
                <xsl:variable name="calls" select=".//call"/>
                <xsl:variable name="called-by" select="$procedures[.//call[@name = $name]]"/>

                <l:procedure name="{$name}">
                    <xsl:copy-of select="ancestor::*/@* except ancestor::*/@entryRule"/>
                    <xsl:variable name="tos">
                        <xsl:for-each select=".//*[./to]">
                            <to name="{./to/@name}">
                                <xsl:for-each select="from">
                                    <from name="{@name}"/>
                                </xsl:for-each>
                            </to>
                        </xsl:for-each>
                    </xsl:variable>
                    <r:graph>
                        <xsl:for-each-group select="$tos/to" group-by="@name">
                            <xsl:sort select="@name"/>
                            <xsl:variable name="froms" select="current-group()/from"/>
                            <r:to name="{current-grouping-key()}">
                                <xsl:for-each-group select="$froms" group-by="@name">
                                    <xsl:sort select="@name"/>
                                    <r:from name="{current-grouping-key()}"/>
                                </xsl:for-each-group>
                            </r:to>
                        </xsl:for-each-group>
                    </r:graph>

                    <l:referenced-tables>
                        <xsl:for-each-group select=".//(./to | ./from)" group-by="@name">
                            <xsl:variable name="reads" select="exists(current-group()/self::from)"/>
                            <xsl:variable name="writes" select="exists(current-group()/self::to)"/>
                            <xsl:variable name="role">
                                <xsl:choose>
                                    <xsl:when test="$writes and $reads">read/write</xsl:when>
                                    <xsl:when test="$writes">write</xsl:when>
                                    <xsl:when test="$reads">read</xsl:when>
                                    <xsl:otherwise>none</xsl:otherwise>
                                </xsl:choose>
                            </xsl:variable>
                            <l:table name="{current-grouping-key()}" role="{$role}"/>
                        </xsl:for-each-group>
                    </l:referenced-tables>


                    <xsl:if test="$calls">
                        <l:calls>
                            <xsl:for-each-group select="$calls" group-by="string-join((@name,@package),'.')">
                                <xsl:variable name="first" select="current-group()[1]"/>
                                <l:call>
                                    <xsl:copy-of select="$first/@* except $first/@type"/>
                                </l:call>
                            </xsl:for-each-group>
                        </l:calls>
                    </xsl:if>
                    <xsl:if test="$called-by">
                        <l:called-by>
                            <xsl:for-each-group select="$called-by" group-by="string-join((@name,@package),'.')">
                                <xsl:variable name="first" select="current-group()[1]"/>
                                <l:procedure>
                                    <xsl:copy-of select="$first/@* except $first/@type"/>
                                </l:procedure>
                            </xsl:for-each-group>
                        </l:called-by>
                    </xsl:if>
                </l:procedure>
            </xsl:for-each>

        </l:procedures>
        <xsl:message>end scan {$schema}</xsl:message>
    </xsl:template>


</xsl:stylesheet>
